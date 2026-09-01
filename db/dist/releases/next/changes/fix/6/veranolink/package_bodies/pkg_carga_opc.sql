-- liquibase formatted sql
-- changeset VERANOLINK:1788300192128 stripComments:false  logicalFilePath:fix\6\veranolink\package_bodies\pkg_carga_opc.sql
-- sqlcl_snapshot db/src/database/veranolink/package_bodies/pkg_carga_opc.sql:null:1ee10b6d13a967d00625ae0b55b9304a0c0852f9:create

create or replace package body veranolink.pkg_carga_opc as

    c_id_path_context         constant number := 305; -- endpoint de Proyecto (api/restapi/project, GET) reutilizado
    c_company                 constant varchar2(50) := 'YPF';
    c_environment             constant number := 2;
    c_alias                   constant varchar2(10) := 'OPC';
    c_udf_integracion         constant varchar2(100) := 'YPF | UDF_PRY015_Integración Sequence';
    c_udf_contract_number     constant varchar2(100) := 'YPF | UDF_PRY010_Contrato';

    -- (PATH_CONTEXT = 'api/restapi/wbs/project', tipo GET / ID_VL_CALL_TYPE = 1).
    c_id_path_context_wbs     constant number := 706;

    -- Endpoint 'View Activities by Project, Code Type, and Code Value'
    -- (PATH_CONTEXT='api/restapi/activity/project', tipo GET / ID_VL_CALL_TYPE=1).
    c_id_path_context_act     constant number := 12;

    -- Filtro de fase: solo se cargan las actividades marcadas con 'Construccion'
    c_codetype_id_fase        constant number := 6104;
    c_codevalue_fase          constant varchar2(10) := 'C';

    -- Baselines a incluir en la respuesta del endpoint del cronograma actual.
    c_include_baseline_fields constant varchar2(30) := 'ORIGINAL,CURRENT';

    -- ================= LINEA BASE =================

    -- Endpoint 'View Project Baseline By Project'
    -- PATH_CONTEXT esperado: 'api/restapi/action/baseline/project'  (GET / ID_VL_CALL_TYPE = 1)
    c_id_path_context_bl_list constant number := 7;

    -- Endpoint 'View Activities by Baseline'
    -- PATH_CONTEXT esperado: 'api/restapi/activity/baseline/data'   (GET / ID_VL_CALL_TYPE = 1)
    c_id_path_context_bl_act  constant number := 9;

    -- Campos minimos solicitados al endpoint de actividades por linea base.
    -- Reduce drasticamente el payload. codeValuesActivity se pide porque el
    -- filtrado por Fase NO se puede hacer en el servidor: el header 'filters'
    -- no opera sobre colecciones anidadas.
    c_select_bl_act           constant varchar2(300) := 'activityId, activityCode, activityName, activityType, wbsId, '
                                              || 'plannedLaborUnits, startDate, finishDate, updateDate, '
                                              || 'codeValuesActivity{codeTypeId, codeValueCode}';

    -- Tamano de lote para el reintento por activityId.
    -- Cada id ocupa ~22 caracteres en el header ('activityId = 1386856, '),
    -- por lo que 50 ids dan ~1.100 caracteres, holgado frente al limite.
    -- En la practica el reintento suele ser de 1 o muy pocas actividades.
    c_lote_reintento          constant pls_integer := 50;

    -- Ancho de la etiqueta "PROJECT_ID | PROJECT_CODE" en la salida por consola.
    c_ancho_etiqueta          constant pls_integer := 40;

    ------------------------------------------------------------------
    -- F_ETIQUETA_PROY (privada)
    -- Arma la etiqueta de proyecto usada en todas las lineas de salida,
    -- para que las columnas queden alineadas entre procedimientos.
    ------------------------------------------------------------------
    function f_etiqueta_proy (
        p_project_id   in number,
        p_project_code in varchar2
    ) return varchar2 is
    begin
        return '  '
               || rpad(
            substr(p_project_id
                   || ' | '
                   || p_project_code, 1, c_ancho_etiqueta),
            c_ancho_etiqueta
        );
    end f_etiqueta_proy;

    ------------------------------------------------------------------
    -- F_GET_UDF_VALOR (privada)
    ------------------------------------------------------------------
    function f_get_udf_valor (
        p_row_index   in pls_integer,
        p_column_name in varchar2
    ) return varchar2 is
        l_count      pls_integer;
        l_text_val   varchar2(4000);
        l_number_val number;
        l_date_val   varchar2(50);
    begin
        l_count := apex_json.get_count(
            p_path => '[%d].configuredFields',
            p0     => p_row_index
        );
        for j in 1..nvl(l_count, 0) loop
            if apex_json.get_varchar2(
                p_path => '[%d].configuredFields[%d].columnName',
                p0     => p_row_index,
                p1     => j
            ) = p_column_name then
                l_text_val := apex_json.get_varchar2(
                    p_path => '[%d].configuredFields[%d].textValue',
                    p0     => p_row_index,
                    p1     => j
                );

                if l_text_val is not null then
                    return l_text_val;
                end if;
                begin
                    l_number_val := apex_json.get_number(
                        p_path => '[%d].configuredFields[%d].numberValue',
                        p0     => p_row_index,
                        p1     => j
                    );

                    if l_number_val is not null then
                        return to_char(l_number_val);
                    end if;
                exception
                    when others then
                        null;
                end;

                l_date_val := apex_json.get_varchar2(
                    p_path => '[%d].configuredFields[%d].dateValue',
                    p0     => p_row_index,
                    p1     => j
                );

                if l_date_val is not null then
                    return l_date_val;
                end if;
                exit;
            end if;
        end loop;

        return null;
    end f_get_udf_valor;

    ------------------------------------------------------------------
    -- F_ISO_TO_TS (privada)
    -- Convierte una cadena ISO 8601 a TIMESTAMP. Toma los primeros 19
    -- caracteres, asi que tolera milisegundos o timezone al final.
    ------------------------------------------------------------------
    function f_iso_to_ts (
        p_iso in varchar2
    ) return timestamp is
    begin
        if p_iso is null then
            return null;
        end if;
        return to_timestamp ( replace(
            substr(p_iso, 1, 19),
            'T',
            ' '
        ),
        'YYYY-MM-DD HH24:MI:SS' );

    exception
        when others then
            return null;
    end f_iso_to_ts;

    ------------------------------------------------------------------
    -- CARGAR_PROYECTOS
    -- CAMBIO: ahora tambien pobla WORKSPACE_CODE, requerido por el
    -- endpoint de actividades por linea base (que no acepta projectId).
    ------------------------------------------------------------------
    procedure cargar_proyectos is

        type t_foto_rec is record (
                project_id      number,
                contract_number varchar2(50)
        );
        type t_foto_tab is
            table of t_foto_rec index by pls_integer;
        l_foto           t_foto_tab;
        type t_nuevo_rec is record (
                project_id      number,
                project_code    varchar2(60),
                project_name    varchar2(255),
                status          varchar2(20),
                contract_number varchar2(50),
                estado          varchar2(20),
                workspace_code  varchar2(60)
        );
        type t_nuevo_tab is
            table of t_nuevo_rec index by pls_integer;
        l_nuevos         t_nuevo_tab;
        l_token_seed     clob;
        l_response       clob;
        l_count          pls_integer;
        c_filter_url     varchar2(500);
        l_project_id     number;
        l_project_code   varchar2(60);
        l_project_name   varchar2(255);
        l_status         varchar2(20);
        l_contract_num   varchar2(50);
        l_workspace_code varchar2(60);
        l_ok             pls_integer := 0;
        l_duplicados     pls_integer := 0;
        l_congelados     pls_integer := 0;
        l_omitidos       pls_integer := 0;
        l_idx            pls_integer := 0;

        function f_contrato_previo (
            p_project_id number
        ) return varchar2 is
        begin
            for i in 1..l_foto.count loop
                if l_foto(i).project_id = p_project_id then
                    return l_foto(i).contract_number;
                end if;
            end loop;

            return null;
        end f_contrato_previo;

        function f_cuenta_en_nuevos (
            p_contract varchar2
        ) return pls_integer is
            l_c pls_integer := 0;
        begin
            for i in 1..l_nuevos.count loop
                if l_nuevos(i).contract_number = p_contract then
                    l_c := l_c + 1;
                end if;
            end loop;

            return l_c;
        end f_cuenta_en_nuevos;

    begin
        for r in (
            select
                project_id,
                contract_number
            from
                tbl_project
        ) loop
            l_idx := l_idx + 1;
            l_foto(l_idx).project_id := r.project_id;
            l_foto(l_idx).contract_number := r.contract_number;
        end loop;

        l_token_seed := vl_pkg_rest_services.vl_fn_rest_gettoken(c_alias, c_company, c_environment);
        c_filter_url := 'configuredField/'
                        || c_udf_integracion
                        || '/TRUE';
        l_response := vl_pkg_rest_services.vl_fn_rest_services(
            iv_filterurl     => c_filter_url,
            iv_bodyrequest   => null,
            iv_projectid     => null,
            iv_alias         => c_alias,
            iv_company       => c_company,
            iv_methodcontext => c_id_path_context,
            iv_environment   => c_environment
        );

        if l_response is null then
            raise_application_error(-20001, 'VL_FN_REST_SERVICES devolvio NULL - revisar VL_TOKENS, company, environment o ID_VL_PATH_CONTEXT.'
            );
        elsif l_response in ( '404', '204', '500', '401' ) then
            raise_application_error(-20002, 'Error al consultar OPC (proyectos): codigo ' || l_response);
        end if;

        apex_json.parse(l_response);
        l_count := apex_json.get_count(p_path => '.');
        l_idx := 0;
        for i in 1..l_count loop
            l_project_id := apex_json.get_number(
                p_path => '[%d].projectId',
                p0     => i
            );
            l_project_code := apex_json.get_varchar2(
                p_path => '[%d].projectCode',
                p0     => i
            );
            l_project_name := apex_json.get_varchar2(
                p_path => '[%d].projectName',
                p0     => i
            );
            l_status := apex_json.get_varchar2(
                p_path => '[%d].status',
                p0     => i
            );
            l_contract_num := f_get_udf_valor(i, c_udf_contract_number);
            l_workspace_code := apex_json.get_varchar2(
                p_path => '[%d].workspaceCode',
                p0     => i
            );
            if l_status != 'ACTIVE'
            or l_contract_num is null then
                l_omitidos := l_omitidos + 1;
                continue;
            end if;

            l_idx := l_idx + 1;
            l_nuevos(l_idx).project_id := l_project_id;
            l_nuevos(l_idx).project_code := l_project_code;
            l_nuevos(l_idx).project_name := l_project_name;
            l_nuevos(l_idx).status := l_status;
            l_nuevos(l_idx).contract_number := l_contract_num;
            l_nuevos(l_idx).estado := null;
            l_nuevos(l_idx).workspace_code := l_workspace_code;
        end loop;

        for i in 1..l_nuevos.count loop
            declare
                l_contrato_previo     varchar2(50);
                l_conflicto_existente number;
            begin
                l_contrato_previo := f_contrato_previo(l_nuevos(i).project_id);
                if
                    l_contrato_previo is not null
                    and l_contrato_previo != l_nuevos(i).contract_number
                then
                    l_nuevos(i).estado := 'CONTRATO_CAMBIADO';
                    continue;
                end if;

                l_conflicto_existente := 0;
                for k in 1..l_foto.count loop
                    if
                        l_foto(k).contract_number = l_nuevos(i).contract_number
                        and l_foto(k).project_id != l_nuevos(i).project_id
                    then
                        l_conflicto_existente := 1;
                        exit;
                    end if;
                end loop;

                if l_conflicto_existente = 1 then
                    l_nuevos(i).estado := 'DUPLICADO';
                    continue;
                end if;

                if f_cuenta_en_nuevos(l_nuevos(i).contract_number) > 1 then
                    l_nuevos(i).estado := 'DUPLICADO';
                    continue;
                end if;

                l_nuevos(i).estado := 'OK';
            end;
        end loop;

        dbms_output.put_line('------------------------------ PROYECTOS ---------------------------------------');
        for i in 1..l_nuevos.count loop
            if l_nuevos(i).estado = 'CONTRATO_CAMBIADO' then
                l_congelados := l_congelados + 1;
                dbms_output.put_line(f_etiqueta_proy(l_nuevos(i).project_id,
                                                     l_nuevos(i).project_code) || ' *** CONTRATO CAMBIADO -> CONGELADO ***');

                continue;
            end if;

            merge into tbl_project t
            using (
                select
                    l_nuevos(i).project_id      as project_id,
                    l_nuevos(i).project_code    as project_code,
                    l_nuevos(i).project_name    as project_name,
                    l_nuevos(i).status          as status,
                    l_nuevos(i).contract_number as contract_number,
                    l_nuevos(i).estado          as estado,
                    l_nuevos(i).workspace_code  as workspace_code
                from
                    dual
            ) s on ( t.project_id = s.project_id )
            when matched then update
            set t.project_code = s.project_code,
                t.project_name = s.project_name,
                t.status = s.status,
                t.integracion_flag = 'Y',
                t.contract_number = s.contract_number,
                t.estado_integracion = s.estado,
                t.workspace_code = s.workspace_code,
                t.fecha_carga = systimestamp
            when not matched then
            insert (
                project_id,
                project_code,
                project_name,
                status,
                integracion_flag,
                contract_number,
                estado_integracion,
                workspace_code,
                fecha_carga )
            values
                ( s.project_id,
                  s.project_code,
                  s.project_name,
                  s.status,
                  'Y',
                  s.contract_number,
                  s.estado,
                  s.workspace_code,
                  systimestamp );

            if l_nuevos(i).estado = 'OK' then
                l_ok := l_ok + 1;
                dbms_output.put_line(f_etiqueta_proy(l_nuevos(i).project_id,
                                                     l_nuevos(i).project_code)
                                     || ' OK        Contrato: '
                                     || rpad(l_nuevos(i).contract_number,
                                             14)
                                     || ' Workspace: ' || nvl(l_nuevos(i).workspace_code,
                                                              '-'));

            elsif l_nuevos(i).estado = 'DUPLICADO' then
                l_duplicados := l_duplicados + 1;
                dbms_output.put_line(f_etiqueta_proy(l_nuevos(i).project_id,
                                                     l_nuevos(i).project_code)
                                     || ' *** CONTRATO DUPLICADO ('
                                     || l_nuevos(i).contract_number || ') ***');

            end if;

        end loop;

        dbms_output.put_line('Proyectos OK: '
                             || l_ok
                             || ' | Duplicados: '
                             || l_duplicados
                             || ' | Contrato cambiado: '
                             || l_congelados
                             || ' | Omitidos por filtros: ' || l_omitidos);

        commit;
    exception
        when others then
            rollback;
            raise;
    end cargar_proyectos;

    ------------------------------------------------------------------
    -- CARGAR_WBS  (sin cambios funcionales)
    -- Carga la jerarquia WBS del cronograma actual filtrada por Fase.
    -- Doble validacion del updateDate: el header 'filters' es solo una
    -- optimizacion; la decision real la toma este codigo comparando contra
    -- MAX(UPDATEDATE) por WBS_ID.
    --
    -- IMPORTANTE: esta tabla es la fuente de la ESTRUCTURA jerarquica.
    -- Los paths que guarda son los ACTUALES de OPC, que pueden diferir de
    -- los que Ecosys tiene si hubo renombrados aun no sincronizados.
    ------------------------------------------------------------------
    procedure cargar_wbs is

        l_token_seed          clob;
        l_response            clob;
        l_count               pls_integer;
        l_max_updatedate_proy timestamp;
        l_max_updatedate_wbs  timestamp;
        l_header_name         varchar2(50);
        l_header_value        varchar2(200);
        l_filter_url          varchar2(500);
        l_wbs_id              number;
        l_wbs_code            varchar2(60);
        l_wbs_name            varchar2(255);
        l_wbs_path            varchar2(4000);
        l_updatedate_txt      varchar2(50);
        l_updatedate_ts       timestamp;
        l_action              varchar2(10);
        l_total_create        pls_integer := 0;
        l_total_update        pls_integer := 0;
        l_total_ignora        pls_integer := 0;
        l_proy_procesados     pls_integer := 0;

        -- Contadores por proyecto (solo para la salida por consola)
        l_p_create            pls_integer := 0;
        l_p_update            pls_integer := 0;
        l_p_ignora            pls_integer := 0;
    begin
        l_token_seed := vl_pkg_rest_services.vl_fn_rest_gettoken(c_alias, c_company, c_environment);
        dbms_output.put_line('--------------------------------- WBS ---------------------------------------------');
        for proy in (
            select
                project_id,
                project_code
            from
                tbl_project
            where
                    trunc(fecha_carga) = trunc(sysdate)
                and estado_integracion = 'OK'
            order by
                project_id
        ) loop
            l_proy_procesados := l_proy_procesados + 1;
            l_p_create := 0;
            l_p_update := 0;
            l_p_ignora := 0;
            select
                max(updatedate)
            into l_max_updatedate_proy
            from
                tbl_wbs
            where
                project_id = proy.project_id;

            if l_max_updatedate_proy is null then
                l_header_name := null;
                l_header_value := null;
            else
                l_header_name := 'filters';
                l_header_value := 'updateDate > ' || to_char(l_max_updatedate_proy, 'YYYY-MM-DD"T"HH24:MI:SS');
            end if;

            l_filter_url := to_char(proy.project_id)
                            || '/codeType/'
                            || to_char(c_codetype_id_fase)
                            || '/codeValue/'
                            || c_codevalue_fase;

            l_response := vl_pkg_rest_services.vl_fn_rest_services(
                iv_filterurl          => l_filter_url,
                iv_bodyrequest        => null,
                iv_projectid          => null,
                iv_alias              => c_alias,
                iv_company            => c_company,
                iv_methodcontext      => c_id_path_context_wbs,
                iv_environment        => c_environment,
                iv_extra_header_name  => l_header_name,
                iv_extra_header_value => l_header_value
            );

            if l_response is null then
                raise_application_error(-20003, 'VL_FN_REST_SERVICES devolvio NULL en WBS para el proyecto ' || proy.project_id);
            elsif l_response = '204' then
                dbms_output.put_line(f_etiqueta_proy(proy.project_id, proy.project_code) || ' CREATE: 0     UPDATE: 0     Sin cambios: 0'
                );

                continue;
            elsif l_response in ( '404', '500', '401' ) then
                raise_application_error(-20004, 'Error al consultar WBS del proyecto '
                                                || proy.project_id
                                                || ': codigo '
                                                || l_response);
            end if;

            apex_json.parse(l_response);
            l_count := apex_json.get_count(p_path => '.');
            for i in 1..l_count loop
                l_wbs_id := apex_json.get_number(
                    p_path => '[%d].wbsId',
                    p0     => i
                );
                l_wbs_code := utl_i18n.unescape_reference(apex_json.get_varchar2(
                    p_path => '[%d].wbsCode',
                    p0     => i
                ));

                l_wbs_name := utl_i18n.unescape_reference(apex_json.get_varchar2(
                    p_path => '[%d].wbsName',
                    p0     => i
                ));

                l_wbs_path := utl_i18n.unescape_reference(apex_json.get_varchar2(
                    p_path => '[%d].wbsPath',
                    p0     => i
                ));

                l_updatedate_txt := apex_json.get_varchar2(
                    p_path => '[%d].updateDate',
                    p0     => i
                );
                l_updatedate_ts := to_timestamp ( replace(l_updatedate_txt, 'T', ' '),
                'YYYY-MM-DD HH24:MI:SS' );
                select
                    max(updatedate)
                into l_max_updatedate_wbs
                from
                    tbl_wbs
                where
                    wbs_id = l_wbs_id;

                if l_max_updatedate_wbs is null then
                    l_action := 'CREATE';
                elsif l_updatedate_ts > l_max_updatedate_wbs then
                    l_action := 'UPDATE';
                else
                    l_total_ignora := l_total_ignora + 1;
                    l_p_ignora := l_p_ignora + 1;
                    continue;
                end if;

                insert into tbl_wbs (
                    project_id,
                    wbs_id,
                    wbs_code,
                    wbs_name,
                    wbs_path,
                    type,
                    updatedate,
                    action
                ) values
                    ( proy.project_id,
                      l_wbs_id,
                      l_wbs_code,
                      l_wbs_name,
                      l_wbs_path,
                      'WBS',
                      l_updatedate_ts,
                      l_action );

                if l_action = 'CREATE' then
                    l_total_create := l_total_create + 1;
                    l_p_create := l_p_create + 1;
                else
                    l_total_update := l_total_update + 1;
                    l_p_update := l_p_update + 1;
                end if;

            end loop;

            dbms_output.put_line(f_etiqueta_proy(proy.project_id, proy.project_code)
                                 || ' CREATE: '
                                 || rpad(l_p_create, 5)
                                 || ' UPDATE: '
                                 || rpad(l_p_update, 5)
                                 || ' Sin cambios: ' || l_p_ignora);

        end loop;

        dbms_output.put_line('WBS - Proyectos procesados: '
                             || l_proy_procesados
                             || ' | CREATE: '
                             || l_total_create
                             || ' | UPDATE: '
                             || l_total_update
                             || ' | Ignorados (sin cambio real): ' || l_total_ignora);

        commit;
    exception
        when others then
            rollback;
            raise;
    end cargar_wbs;

    ------------------------------------------------------------------
    -- CARGAR_BASELINES
    -- Consulta las lineas base de cada proyecto vigente y mantiene el
    -- historico de las que han estado marcadas como ORIGINAL o CURRENT.
    -- Las lineas base con tipo vacio (NONE) se descartan.
    --
    -- Por cada proyecto:
    --   1. Lee la lista de LB desde OPC.
    --   2. Inserta o reactiva las combinaciones proyecto+baseline+tipo.
    --   3. Marca VIGENTE='N' + FECHA_DESMARCADO a las que ya no aparecen.
    --
    -- Si un proyecto queda sin ninguna fila vigente, su integracion queda
    -- pausada automaticamente: cargar_actividades_baseline no lo procesa.
    ------------------------------------------------------------------
    procedure cargar_baselines is

        l_token_seed      clob;
        l_response        clob;
        l_count           pls_integer;
        l_filter_url      varchar2(500);
        l_bl_id           number;
        l_bl_name         varchar2(255);
        l_bl_type         varchar2(20);
        l_bl_time         timestamp;
        l_bl_data_dt      timestamp;
        l_bl_upd_dt       timestamp;

        -- IDs vistos en esta corrida para el proyecto (para detectar desmarcados)
        type t_vistos_tab is
            table of varchar2(100) index by pls_integer;
        l_vistos          t_vistos_tab;
        l_v_idx           pls_integer;
        l_registradas     pls_integer := 0;
        l_desmarcadas     pls_integer := 0;
        l_proy_pausados   pls_integer := 0;
        l_proy_procesados pls_integer := 0;
        l_vigentes        pls_integer;

        -- Contadores y detalle por proyecto (solo para la salida por consola)
        l_p_vigentes      pls_integer := 0;
        l_p_desmarcadas   pls_integer := 0;
        l_p_detalle       varchar2(500);

        function f_fue_visto (
            p_clave varchar2
        ) return boolean is
        begin
            for i in 1..l_vistos.count loop
                if l_vistos(i) = p_clave then
                    return true;
                end if;
            end loop;

            return false;
        end f_fue_visto;

    begin
        l_token_seed := vl_pkg_rest_services.vl_fn_rest_gettoken(c_alias, c_company, c_environment);
        dbms_output.put_line('------------------------------ BASELINES ---------------------------------------');
        for proy in (
            select
                project_id,
                project_code
            from
                tbl_project
            where
                    trunc(fecha_carga) = trunc(sysdate)
                and estado_integracion = 'OK'
            order by
                project_id
        ) loop
            l_proy_procesados := l_proy_procesados + 1;
            l_vistos.delete;
            l_v_idx := 0;
            l_p_vigentes := 0;
            l_p_desmarcadas := 0;
            l_p_detalle := null;

            -- El endpoint recibe el projectId como ultimo segmento de la ruta
            l_filter_url := to_char(proy.project_id);
            l_response := vl_pkg_rest_services.vl_fn_rest_services(
                iv_filterurl     => l_filter_url,
                iv_bodyrequest   => null,
                iv_projectid     => null,
                iv_alias         => c_alias,
                iv_company       => c_company,
                iv_methodcontext => c_id_path_context_bl_list,
                iv_environment   => c_environment
            );

            if l_response is null then
                raise_application_error(-20007, 'VL_FN_REST_SERVICES devolvio NULL en Baselines para el proyecto ' || proy.project_id
                );
            elsif l_response = '204' then
                l_count := 0;
            elsif l_response in ( '404', '500', '401' ) then
                raise_application_error(-20008, 'Error al consultar Baselines del proyecto '
                                                || proy.project_id
                                                || ': codigo '
                                                || l_response);
            else
                apex_json.parse(l_response);
                l_count := apex_json.get_count(p_path => '.');
            end if;

            for i in 1..nvl(l_count, 0) loop
                l_bl_type := apex_json.get_varchar2(
                    p_path => '[%d].type',
                    p0     => i
                );

                -- Solo interesan ORIGINAL y CURRENT. Las de tipo vacio se ignoran.
                if l_bl_type not in ( 'ORIGINAL', 'CURRENT' ) then
                    continue;
                end if;
                l_bl_id := apex_json.get_number(
                    p_path => '[%d].projectBaselineId',
                    p0     => i
                );
                l_bl_name := apex_json.get_varchar2(
                    p_path => '[%d].name',
                    p0     => i
                );
                l_bl_time := f_iso_to_ts(apex_json.get_varchar2(
                    p_path => '[%d].time',
                    p0     => i
                ));

                l_bl_data_dt := f_iso_to_ts(apex_json.get_varchar2(
                    p_path => '[%d].dataDate',
                    p0     => i
                ));

                l_bl_upd_dt := f_iso_to_ts(apex_json.get_varchar2(
                    p_path => '[%d].updateDate',
                    p0     => i
                ));

                l_v_idx := l_v_idx + 1;
                l_vistos(l_v_idx) := to_char(l_bl_id)
                                     || '|'
                                     || l_bl_type;
                merge into tbl_project_baseline t
                using (
                    select
                        proy.project_id as project_id,
                        l_bl_id         as baseline_id,
                        l_bl_type       as baseline_type
                    from
                        dual
                ) s on ( t.project_id = s.project_id
                         and t.project_baseline_id = s.baseline_id
                         and t.baseline_type = s.baseline_type )
                when matched then update
                set t.baseline_name = l_bl_name,
                    t.baseline_time = l_bl_time,
                    t.baseline_data_date = l_bl_data_dt,
                    t.baseline_update_date = l_bl_upd_dt,
                    t.vigente = 'Y',
                    t.fecha_desmarcado = null
                when not matched then
                insert (
                    project_id,
                    project_baseline_id,
                    baseline_name,
                    baseline_type,
                    baseline_time,
                    baseline_data_date,
                    baseline_update_date,
                    vigente,
                    intentos,
                    fecha_carga )
                values
                    ( s.project_id,
                      s.baseline_id,
                      l_bl_name,
                      s.baseline_type,
                      l_bl_time,
                      l_bl_data_dt,
                      l_bl_upd_dt,
                      'Y',
                      0,
                      systimestamp );

                l_registradas := l_registradas + 1;
                l_p_vigentes := l_p_vigentes + 1;
                l_p_detalle := substr(
                    case
                        when l_p_detalle is null then
                            ''
                        else
                            l_p_detalle || ', '
                    end
                    || l_bl_type
                    || '='
                    || l_bl_name, 1, 500);

            end loop;

            -- Desmarcar las filas del proyecto que ya no vinieron con ese tipo
            for fila in (
                select
                    id_fila,
                    project_baseline_id,
                    baseline_type
                from
                    tbl_project_baseline
                where
                        project_id = proy.project_id
                    and vigente = 'Y'
            ) loop
                if not f_fue_visto(to_char(fila.project_baseline_id)
                                   || '|' || fila.baseline_type) then
                    update tbl_project_baseline
                    set
                        vigente = 'N',
                        fecha_desmarcado = systimestamp
                    where
                        id_fila = fila.id_fila;

                    l_desmarcadas := l_desmarcadas + 1;
                    l_p_desmarcadas := l_p_desmarcadas + 1;
                end if;
            end loop;

            select
                count(*)
            into l_vigentes
            from
                tbl_project_baseline
            where
                    project_id = proy.project_id
                and vigente = 'Y';

            if l_vigentes = 0 then
                l_proy_pausados := l_proy_pausados + 1;
                dbms_output.put_line(f_etiqueta_proy(proy.project_id, proy.project_code) || ' *** SIN LINEA BASE MARCADA -> PAUSADO ***'
                );

            else
                dbms_output.put_line(f_etiqueta_proy(proy.project_id, proy.project_code)
                                     || ' Vigentes: '
                                     || rpad(l_p_vigentes, 4)
                                     || ' Desmarcadas: '
                                     || rpad(l_p_desmarcadas, 4)
                                     || ' ['
                                     || nvl(l_p_detalle, '-') || ']');
            end if;

        end loop;

        dbms_output.put_line('Baselines - Proyectos procesados: '
                             || l_proy_procesados
                             || ' | LB vigentes detectadas: '
                             || l_registradas
                             || ' | Desmarcadas: '
                             || l_desmarcadas
                             || ' | Proyectos pausados: ' || l_proy_pausados);

        commit;
    exception
        when others then
            rollback;
            raise;
    end cargar_baselines;

    ------------------------------------------------------------------
    -- PROCESAR_RESPUESTA_BL (privada)
    -- Parsea la respuesta del endpoint de actividades por linea base e
    -- inserta en TBL_ACTIVITY_BASELINE las que tienen Fase = Construccion.
    -- El filtro por fase se hace aqui porque el servidor no puede filtrar
    -- sobre la coleccion anidada codeValuesActivity.
    ------------------------------------------------------------------
    procedure procesar_respuesta_bl (
        p_response    in clob,
        p_project_id  in number,
        p_bl_id       in number,
        p_bl_type     in varchar2,
        p_origen      in varchar2,
        p_insertadas  in out pls_integer,
        p_descartadas in out pls_integer
    ) is

        l_count         pls_integer;
        l_cv_count      pls_integer;
        l_es_fase_c     boolean;
        l_activity_id   number;
        l_activity_code varchar2(60);
        l_activity_name varchar2(255);
        l_activity_type varchar2(30);
        l_wbs_id        number;
        l_planned_lu    number;
        l_bl_start      timestamp;
        l_bl_finish     timestamp;
        l_updatedate_ts timestamp;
    begin
        if p_response is null then
            raise_application_error(-20009, 'VL_FN_REST_SERVICES devolvio NULL en Actividades de linea base (proyecto '
                                            || p_project_id
                                            || ')');
        elsif p_response = '204' then
            return;
        elsif p_response in ( '404', '500', '401' ) then
            raise_application_error(-20010, 'Error al consultar Actividades de linea base del proyecto '
                                            || p_project_id
                                            || ': codigo '
                                            || p_response);
        end if;

        apex_json.parse(p_response);
        l_count := apex_json.get_count(p_path => '.');
        for i in 1..nvl(l_count, 0) loop
            -- Filtro Fase = Construccion en cliente
            l_es_fase_c := false;
            l_cv_count := apex_json.get_count(
                p_path => '[%d].codeValuesActivity',
                p0     => i
            );
            for j in 1..nvl(l_cv_count, 0) loop
                if
                    apex_json.get_number(
                        p_path => '[%d].codeValuesActivity[%d].codeTypeId',
                        p0     => i,
                        p1     => j
                    ) = c_codetype_id_fase
                    and apex_json.get_varchar2(
                        p_path => '[%d].codeValuesActivity[%d].codeValueCode',
                        p0     => i,
                        p1     => j
                    ) = c_codevalue_fase
                then
                    l_es_fase_c := true;
                    exit;
                end if;
            end loop;

            if not l_es_fase_c then
                p_descartadas := p_descartadas + 1;
                continue;
            end if;
            l_activity_id := apex_json.get_number(
                p_path => '[%d].activityId',
                p0     => i
            );
            l_activity_code := utl_i18n.unescape_reference(apex_json.get_varchar2(
                p_path => '[%d].activityCode',
                p0     => i
            ));

            l_activity_name := utl_i18n.unescape_reference(apex_json.get_varchar2(
                p_path => '[%d].activityName',
                p0     => i
            ));

            l_activity_type := apex_json.get_varchar2(
                p_path => '[%d].activityType',
                p0     => i
            );
            l_wbs_id := apex_json.get_number(
                p_path => '[%d].wbsId',
                p0     => i
            );
            l_planned_lu := apex_json.get_number(
                p_path => '[%d].plannedLaborUnits',
                p0     => i
            );

            -- En este endpoint startDate/finishDate son las fechas CONGELADAS
            -- de la linea base, no las del cronograma vivo.
            l_bl_start := f_iso_to_ts(apex_json.get_varchar2(
                p_path => '[%d].startDate',
                p0     => i
            ));

            l_bl_finish := f_iso_to_ts(apex_json.get_varchar2(
                p_path => '[%d].finishDate',
                p0     => i
            ));

            l_updatedate_ts := f_iso_to_ts(apex_json.get_varchar2(
                p_path => '[%d].updateDate',
                p0     => i
            ));

            insert into tbl_activity_baseline (
                project_id,
                project_baseline_id,
                baseline_type,
                wbs_id,
                activity_id,
                activity_code,
                activity_name,
                planned_labor_units,
                bl_start_date,
                bl_finish_date,
                activity_type_opc,
                type,
                origen_carga,
                updatedate
            ) values
                ( p_project_id,
                  p_bl_id,
                  p_bl_type,
                  l_wbs_id,
                  l_activity_id,
                  l_activity_code,
                  l_activity_name,
                  l_planned_lu,
                  l_bl_start,
                  l_bl_finish,
                  l_activity_type,
                  'Work Package',
                  p_origen,
                  l_updatedate_ts );

            p_insertadas := p_insertadas + 1;
        end loop;

    end procesar_respuesta_bl;

    ------------------------------------------------------------------
    -- CARGAR_ACTIVIDADES_BASELINE
    -- Fuente del flujo de CREACION hacia Sequence.
    --
    -- Por cada proyecto se elige UNA sola linea base vigente:
    --   - Si hay CURRENT vigente -> se usa CURRENT.
    --   - Si no hay CURRENT pero hay ORIGINAL vigente Y el proyecto nunca
    --     ha consumido una CURRENT -> se usa ORIGINAL.
    --   - Si no hay ninguna vigente -> el proyecto se salta (pausado).
    -- Nunca se retrocede de CURRENT a ORIGINAL.
    --
    -- Dos modalidades de consumo:
    --   SNAPSHOT  -> la LB no tiene actividades cargadas. Se trae completa.
    --   REINTENTO -> la LB ya tiene snapshot pero hay actividades con
    --                RESULTADO='FALLO' y sin 'OK'. Se reconsultan SOLO esas,
    --                filtrando por activityId, para no alterar las que ya
    --                estan creadas correctamente en Ecosys.
    ------------------------------------------------------------------
    procedure cargar_actividades_baseline is

        l_token_seed     clob;
        l_response       clob;
        l_filter_url     varchar2(1000);
        l_header_name    varchar2(50);
        l_header_value   varchar2(4000);
        l_origen         varchar2(10);
        l_ya_cargada     pls_integer;
        l_pendientes     pls_integer;
        l_wbs_fallidas   pls_integer;
        l_ins_act        pls_integer := 0;
        l_ins_wbs        pls_integer := 0;
        l_descartadas    pls_integer := 0;
        l_proy_snapshot  pls_integer := 0;
        l_proy_reintento pls_integer := 0;
        l_proy_saltados  pls_integer := 0;
        l_lista_ids      varchar2(4000);
        l_en_lote        pls_integer;

        -- Marcas para calcular el aporte de cada proyecto sobre los
        -- acumulados globales (procesar_respuesta_bl suma sobre el total).
        l_act_antes      pls_integer := 0;
        l_desc_antes     pls_integer := 0;
        l_p_act          pls_integer := 0;
        l_p_desc         pls_integer := 0;
        l_p_wbs          pls_integer := 0;
    begin
        l_token_seed := vl_pkg_rest_services.vl_fn_rest_gettoken(c_alias, c_company, c_environment);
        dbms_output.put_line('----------------------- ACTIVIDADES LINEA BASE --------------------------');

        -- Advertencia previa: proyectos activos que quedaron SIN linea base
        -- elegible. Ocurre cuando se desmarca la CURRENT y solo queda una
        -- ORIGINAL, pero el proyecto ya habia consumido una CURRENT: no se
        -- retrocede a ORIGINAL, asi que el proyecto queda pausado por completo
        -- (no entra al loop de abajo y tampoco se actualiza por cronograma).
        -- Se reactiva en cuanto se marque una CURRENT vigente en OPC.
        for sin_lb in (
            select
                p.project_id,
                p.project_code
            from
                tbl_project p
            where
                    p.estado_integracion = 'OK'
                and p.workspace_code is not null
                and not exists (
                    select
                        1
                    from
                        tbl_project_baseline b
                    where
                            b.project_id = p.project_id
                        and b.vigente = 'Y'
                        and ( b.baseline_type = 'CURRENT'
                              or not exists (
                            select
                                1
                            from
                                tbl_project_baseline c
                            where
                                    c.project_id = b.project_id
                                and c.baseline_type = 'CURRENT'
                                and c.fecha_primer_consumo is not null
                        ) )
                )
            order by
                p.project_id
        ) loop
            dbms_output.put_line(f_etiqueta_proy(sin_lb.project_id, sin_lb.project_code)
                                 || ' ADVERTENCIA: no hay linea base Current vigente.' || ' Proyecto pausado (no se crea ni se actualiza).'
                                 );
        end loop;

        for proy in (
            select
                p.project_id,
                p.project_code,
                p.workspace_code,
                b.project_baseline_id,
                b.baseline_type,
                b.id_fila as id_fila_bl
            from
                     tbl_project p
                join (
                    select
                        x.*
                    from
                        (
                            select
                                b.*,
                                row_number()
                                over(partition by b.project_id
                                     order by
                                         case b.baseline_type
                                             when 'CURRENT'  then
                                                 1
                                             when 'ORIGINAL' then
                                                 2
                                         end, b.baseline_time desc
                                ) as rn
                            from
                                tbl_project_baseline b
                            where
                                    b.vigente = 'Y'
                                and ( b.baseline_type = 'CURRENT'
                                      or not exists (
                                    select
                                        1
                                    from
                                        tbl_project_baseline c
                                    where
                                            c.project_id = b.project_id
                                        and c.baseline_type = 'CURRENT'
                                        and c.fecha_primer_consumo is not null
                                ) )
                        ) x
                    where
                        x.rn = 1
                ) b on b.project_id = p.project_id
            where
                    p.estado_integracion = 'OK'
                and p.workspace_code is not null
            order by
                p.project_id
        ) loop
            l_act_antes := l_ins_act;
            l_desc_antes := l_descartadas;
            l_p_wbs := 0;

            -- ¿La LB ya tiene snapshot cargado?
            select
                count(*)
            into l_ya_cargada
            from
                tbl_activity_baseline
            where
                project_baseline_id = proy.project_baseline_id;

            if l_ya_cargada = 0 then
                l_origen := 'SNAPSHOT';
            else
                -- ¿Quedan actividades fallidas sin OK posterior?
                select
                    count(distinct a.activity_id)
                into l_pendientes
                from
                    tbl_activity_baseline a
                where
                        a.project_baseline_id = proy.project_baseline_id
                    and exists (
                        select
                            1
                        from
                            log_opc_sequence l
                        where
                                l.tipo_objeto = 'ACTIVITY'
                            and l.object_id = a.activity_id
                            and l.resultado = 'FALLO'
                    )
                    and not exists (
                        select
                            1
                        from
                            log_opc_sequence l
                        where
                                l.tipo_objeto = 'ACTIVITY'
                            and l.object_id = a.activity_id
                            and l.resultado = 'OK'
                    );

                if l_pendientes = 0 then
                    l_proy_saltados := l_proy_saltados + 1;
                    dbms_output.put_line(f_etiqueta_proy(proy.project_id, proy.project_code)
                                         || ' SIN CAMBIOS EN LB '
                                         || proy.project_baseline_id
                                         || ' ('
                                         || proy.baseline_type || ')');

                    continue;   -- LB completamente OK: no se vuelve a consumir
                end if;

                l_origen := 'REINTENTO';
            end if;

            -- El endpoint usa workspaceCode + projectCode (no acepta projectId).
            -- El baselineName no es necesario: basta el baselineType.
            l_filter_url := '?workspaceCode='
                            || utl_url.escape(proy.workspace_code, true)
                            || '&projectCode='
                            || utl_url.escape(proy.project_code, true)
                            || '&baselineType='
                            || proy.baseline_type;

            if l_origen = 'SNAPSHOT' then
                l_proy_snapshot := l_proy_snapshot + 1;
                -- Solo se usa 'select' (reduce el payload). No se usa 'filters'.
                -- VL_FN_REST_SERVICES admite un unico header extra.
                l_header_name := 'select';
                l_header_value := c_select_bl_act;
                l_response := vl_pkg_rest_services.vl_fn_rest_services(
                    iv_filterurl          => l_filter_url,
                    iv_bodyrequest        => null,
                    iv_projectid          => null,
                    iv_alias              => c_alias,
                    iv_company            => c_company,
                    iv_methodcontext      => c_id_path_context_bl_act,
                    iv_environment        => c_environment,
                    iv_extra_header_name  => l_header_name,
                    iv_extra_header_value => l_header_value
                );

                procesar_respuesta_bl(
                    p_response    => l_response,
                    p_project_id  => proy.project_id,
                    p_bl_id       => proy.project_baseline_id,
                    p_bl_type     => proy.baseline_type,
                    p_origen      => l_origen,
                    p_insertadas  => l_ins_act,
                    p_descartadas => l_descartadas
                );

            else
                l_proy_reintento := l_proy_reintento + 1;
                l_lista_ids := null;
                l_en_lote := 0;
                for act in (
                    select distinct
                        a.activity_id
                    from
                        tbl_activity_baseline a
                    where
                            a.project_baseline_id = proy.project_baseline_id
                        and exists (
                            select
                                1
                            from
                                log_opc_sequence l
                            where
                                    l.tipo_objeto = 'ACTIVITY'
                                and l.object_id = a.activity_id
                                and l.resultado = 'FALLO'
                        )
                        and not exists (
                            select
                                1
                            from
                                log_opc_sequence l
                            where
                                    l.tipo_objeto = 'ACTIVITY'
                                and l.object_id = a.activity_id
                                and l.resultado = 'OK'
                        )
                    order by
                        a.activity_id
                ) loop
                    -- OPC no acepta 'activityId IN (...)'. La unica sintaxis valida
                    -- es repetir la condicion por cada id, separada por coma, que el
                    -- servidor interpreta como OR implicito:
                    --   activityId = 1386856, activityId = 1386857
                    l_lista_ids :=
                        case
                            when l_lista_ids is null then
                                'activityId = ' || to_char(act.activity_id)
                            else
                                l_lista_ids
                                || ', activityId = '
                                || to_char(act.activity_id)
                        end;

                    l_en_lote := l_en_lote + 1;
                    if l_en_lote >= c_lote_reintento then
                        l_header_name := 'filters';
                        l_header_value := l_lista_ids;
                        l_response := vl_pkg_rest_services.vl_fn_rest_services(
                            iv_filterurl          => l_filter_url,
                            iv_bodyrequest        => null,
                            iv_projectid          => null,
                            iv_alias              => c_alias,
                            iv_company            => c_company,
                            iv_methodcontext      => c_id_path_context_bl_act,
                            iv_environment        => c_environment,
                            iv_extra_header_name  => l_header_name,
                            iv_extra_header_value => l_header_value
                        );

                        procesar_respuesta_bl(
                            p_response    => l_response,
                            p_project_id  => proy.project_id,
                            p_bl_id       => proy.project_baseline_id,
                            p_bl_type     => proy.baseline_type,
                            p_origen      => l_origen,
                            p_insertadas  => l_ins_act,
                            p_descartadas => l_descartadas
                        );

                        l_lista_ids := null;
                        l_en_lote := 0;
                    end if;

                end loop;

                -- Lote final incompleto
                if l_lista_ids is not null then
                    l_header_name := 'filters';
                    l_header_value := l_lista_ids;
                    l_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl          => l_filter_url,
                        iv_bodyrequest        => null,
                        iv_projectid          => null,
                        iv_alias              => c_alias,
                        iv_company            => c_company,
                        iv_methodcontext      => c_id_path_context_bl_act,
                        iv_environment        => c_environment,
                        iv_extra_header_name  => l_header_name,
                        iv_extra_header_value => l_header_value
                    );

                    procesar_respuesta_bl(
                        p_response    => l_response,
                        p_project_id  => proy.project_id,
                        p_bl_id       => proy.project_baseline_id,
                        p_bl_type     => proy.baseline_type,
                        p_origen      => l_origen,
                        p_insertadas  => l_ins_act,
                        p_descartadas => l_descartadas
                    );

                end if;

            end if;

            -- ============ Reconstruccion de la jerarquia WBS ============
            -- Solo en SNAPSHOT: en un reintento la jerarquia de esa LB ya existe.
            -- El endpoint de baseline solo entrega el wbsId HOJA (donde cuelga
            -- cada actividad). Los niveles intermedios se reconstruyen buscando
            -- en TBL_WBS los WBS cuyo path es prefijo del path de alguna hoja.
            if l_origen = 'SNAPSHOT' then
                insert into tbl_wbs_baseline (
                    project_id,
                    project_baseline_id,
                    id_tbl_wbs,
                    wbs_id,
                    wbs_code,
                    wbs_name,
                    wbs_path,
                    type,
                    nivel,
                    es_hoja_actividad,
                    updatedate
                )
                    with wbs_ultimo as (
                        select
                            w.*
                        from
                            tbl_wbs w
                        where
                                w.project_id = proy.project_id
                            and w.updatedate = (
                                select
                                    max(w2.updatedate)
                                from
                                    tbl_wbs w2
                                where
                                    w2.wbs_id = w.wbs_id
                            )
                    ), hojas as (
                        select distinct
                            a.wbs_id
                        from
                            tbl_activity_baseline a
                        where
                            a.project_baseline_id = proy.project_baseline_id
                    ), hojas_path as (
                        select
                            w.wbs_id,
                            w.wbs_path
                        from
                                 wbs_ultimo w
                            join hojas h on h.wbs_id = w.wbs_id
                    )
                    select
                        proy.project_id,
                        proy.project_baseline_id,
                        w.id_fila,
                        w.wbs_id,
                        w.wbs_code,
                        w.wbs_name,
                        w.wbs_path,
                        'WBS',
                        length(w.wbs_path) - length(replace(w.wbs_path, '.', '')) + 1,
                        case
                            when exists (
                                select
                                    1
                                from
                                    hojas h
                                where
                                    h.wbs_id = w.wbs_id
                            ) then
                                'Y'
                            else
                                'N'
                        end,
                        w.updatedate
                    from
                        wbs_ultimo w
                    where
                        exists (
                            select
                                1
                            from
                                hojas_path hp
                            where
                                hp.wbs_path = w.wbs_path
                                or hp.wbs_path like w.wbs_path || '.%'
                        )
                  -- Excluye el nivel proyecto (nivel 1, sin punto): en Ecosys ese
                  -- segmento se reemplaza por el CONTRACT_NUMBER.
                        and instr(w.wbs_path, '.') > 0;

                l_p_wbs := sql%rowcount;
                l_ins_wbs := l_ins_wbs + l_p_wbs;
            end if;

            -- ============ Refresco de jerarquia WBS en REINTENTO ============
            -- El SNAPSHOT congela TBL_WBS_BASELINE en el primer consumo. Si una
            -- WBS se creo con un code invalido (p.ej. un punto en el wbsCode), su
            -- creacion en Ecosys falla y el usuario corrige el code en el
            -- cronograma actual (OPC reajusta solo el path del WBS y el de todos
            -- sus descendientes). Esa correccion llega a TBL_WBS pero NUNCA a
            -- TBL_WBS_BASELINE, que la vista de creacion es la que lee -> la WBS
            -- se reintenta indefinidamente con el code viejo.
            --
            -- Solucion: si esta LB tiene alguna WBS en estado FALLO sin OK, se
            -- reconstruye su jerarquia WBS leyendo TBL_WBS fresco (con el code ya
            -- corregido). Es idempotente: las WBS que no cambiaron se reinsertan
            -- identicas y la vista no las reemite (siguen con su OK en el log);
            -- solo las fallidas viajan de nuevo, ya corregidas. Las WBS que nunca
            -- se crearon quedan fuera de la vista de actualizacion por su INNER
            -- JOIN con el estado sincronizado, de modo que no se generan updates
            -- innecesarios.
            if l_origen = 'REINTENTO' then
                select
                    count(*)
                into l_wbs_fallidas
                from
                    tbl_wbs_baseline wb
                where
                        wb.project_baseline_id = proy.project_baseline_id
                    and exists (
                        select
                            1
                        from
                            log_opc_sequence l
                        where
                                l.tipo_objeto = 'WBS'
                            and l.object_id = wb.wbs_id
                            and l.resultado = 'FALLO'
                    )
                    and not exists (
                        select
                            1
                        from
                            log_opc_sequence l
                        where
                                l.tipo_objeto = 'WBS'
                            and l.object_id = wb.wbs_id
                            and l.resultado = 'OK'
                    );

                if l_wbs_fallidas > 0 then
                    -- Se descarta la foto vieja de esta LB y se reconstruye
                    -- completa desde TBL_WBS fresco (misma logica que el SNAPSHOT).
                    delete from tbl_wbs_baseline
                    where
                        project_baseline_id = proy.project_baseline_id;

                    insert into tbl_wbs_baseline (
                        project_id,
                        project_baseline_id,
                        id_tbl_wbs,
                        wbs_id,
                        wbs_code,
                        wbs_name,
                        wbs_path,
                        type,
                        nivel,
                        es_hoja_actividad,
                        updatedate
                    )
                        with wbs_ultimo as (
                            select
                                z.*
                            from
                                (
                                    select
                                        w.*,
                                        row_number()
                                        over(partition by w.wbs_id
                                             order by
                                                 w.fecha_carga desc, w.id_fila desc
                                        ) as rn_wu
                                    from
                                        tbl_wbs w
                                    where
                                        w.project_id = proy.project_id
                                ) z
                            where
                                z.rn_wu = 1
                        ), hojas as (
                            select distinct
                                a.wbs_id
                            from
                                tbl_activity_baseline a
                            where
                                a.project_baseline_id = proy.project_baseline_id
                        ), hojas_path as (
                            select
                                w.wbs_id,
                                w.wbs_path
                            from
                                     wbs_ultimo w
                                join hojas h on h.wbs_id = w.wbs_id
                        )
                        select
                            proy.project_id,
                            proy.project_baseline_id,
                            w.id_fila,
                            w.wbs_id,
                            w.wbs_code,
                            w.wbs_name,
                            w.wbs_path,
                            'WBS',
                            length(w.wbs_path) - length(replace(w.wbs_path, '.', '')) + 1,
                            case
                                when exists (
                                    select
                                        1
                                    from
                                        hojas h
                                    where
                                        h.wbs_id = w.wbs_id
                                ) then
                                    'Y'
                                else
                                    'N'
                            end,
                            w.updatedate
                        from
                            wbs_ultimo w
                        where
                            exists (
                                select
                                    1
                                from
                                    hojas_path hp
                                where
                                    hp.wbs_path = w.wbs_path
                                    or hp.wbs_path like w.wbs_path || '.%'
                            )
                            and instr(w.wbs_path, '.') > 0;

                    l_p_wbs := sql%rowcount;
                    l_ins_wbs := l_ins_wbs + l_p_wbs;
                end if;

            end if;

            update tbl_project_baseline
            set
                intentos = intentos + 1,
                fecha_primer_consumo = nvl(fecha_primer_consumo, systimestamp),
                fecha_ultimo_consumo = systimestamp
            where
                id_fila = proy.id_fila_bl;

            l_p_act := l_ins_act - l_act_antes;
            l_p_desc := l_descartadas - l_desc_antes;
            dbms_output.put_line(f_etiqueta_proy(proy.project_id, proy.project_code)
                                 || ' '
                                 || rpad(l_origen, 10)
                                 || ' Act: '
                                 || rpad(l_p_act, 6)
                                 || ' WBS: '
                                 || rpad(l_p_wbs, 5)
                                 || ' Descartadas: '
                                 || rpad(l_p_desc, 6)
                                 || ' LB: '
                                 || proy.project_baseline_id
                                 || ' ('
                                 || proy.baseline_type || ')');

        end loop;

        dbms_output.put_line('Actividades LB - Snapshot: '
                             || l_proy_snapshot
                             || ' | Reintento: '
                             || l_proy_reintento
                             || ' | LB sin cambios (saltadas): '
                             || l_proy_saltados
                             || ' | Actividades insertadas: '
                             || l_ins_act
                             || ' | Descartadas (fase != C): '
                             || l_descartadas
                             || ' | WBS insertadas: ' || l_ins_wbs);

        commit;
    exception
        when others then
            rollback;
            raise;
    end cargar_actividades_baseline;

    ------------------------------------------------------------------
    -- CARGAR_ACTIVIDADES
    -- Consume el cronograma actual filtrado por Fase=Construccion.
    --
    -- CAMBIO DE ROL: desde el rediseno baseline-driven esta procedure YA NO
    -- es fuente de creacion. Alimenta unicamente el flujo de ACTUALIZACION:
    --   - AT_COMPLETION_LABOR_UNITS -> Hours
    --   - STARTDATE / FINISHDATE    -> fechas CB (Tendencia)
    --
    -- CAMBIO DE ORIGEN: antes se leian actualStart/actualFinish, que son
    -- nulos mientras la actividad no ha iniciado. Ahora se leen
    -- startDate/finishDate, que nunca son nulos: muestran fechas previstas
    -- antes de iniciar y fechas reales despues.
    --
    -- La columna BASELINE ya no se calcula: la eleccion de linea base es una
    -- decision por proyecto que resuelve cargar_baselines.
    ------------------------------------------------------------------
    procedure cargar_actividades is

        l_token_seed          clob;
        l_response            clob;
        l_count               pls_integer;
        l_max_updatedate_proy timestamp;
        l_max_updatedate_act  timestamp;
        l_header_name         varchar2(50);
        l_header_value        varchar2(200);
        l_filter_url          varchar2(500);
        l_activity_id         number;
        l_activity_code       varchar2(60);
        l_activity_name       varchar2(255);
        l_wbs_id              number;
        l_planned_lu          number;
        l_atcompl_lu          number;
        l_ob_start            timestamp;
        l_ob_finish           timestamp;
        l_cb_start            timestamp;
        l_cb_finish           timestamp;
        l_startdate           timestamp;
        l_finishdate          timestamp;
        l_status              varchar2(20);
        l_updatedate_txt      varchar2(50);
        l_updatedate_ts       timestamp;
        l_action              varchar2(10);
        l_total_create        pls_integer := 0;
        l_total_update        pls_integer := 0;
        l_total_ignora        pls_integer := 0;
        l_proy_procesados     pls_integer := 0;

        -- Contadores por proyecto (solo para la salida por consola)
        l_p_create            pls_integer := 0;
        l_p_update            pls_integer := 0;
        l_p_ignora            pls_integer := 0;
    begin
        l_token_seed := vl_pkg_rest_services.vl_fn_rest_gettoken(c_alias, c_company, c_environment);
        dbms_output.put_line('----------------------- ACTIVIDADES CRONOGRAMA --------------------------');
        for proy in (
            select
                project_id,
                project_code
            from
                tbl_project
            where
                    trunc(fecha_carga) = trunc(sysdate)
                and estado_integracion = 'OK'
            order by
                project_id
        ) loop
            l_proy_procesados := l_proy_procesados + 1;
            l_p_create := 0;
            l_p_update := 0;
            l_p_ignora := 0;
            select
                max(updatedate)
            into l_max_updatedate_proy
            from
                tbl_activity
            where
                project_id = proy.project_id;

            if l_max_updatedate_proy is null then
                l_header_name := null;
                l_header_value := null;
            else
                l_header_name := 'filters';
                l_header_value := 'updateDate > ' || to_char(l_max_updatedate_proy, 'YYYY-MM-DD"T"HH24:MI:SS');
            end if;

            l_filter_url := to_char(proy.project_id)
                            || '/codeType/'
                            || to_char(c_codetype_id_fase)
                            || '/codeValue/'
                            || c_codevalue_fase
                            || '?includeBaselineFields='
                            || c_include_baseline_fields;

            l_response := vl_pkg_rest_services.vl_fn_rest_services(
                iv_filterurl          => l_filter_url,
                iv_bodyrequest        => null,
                iv_projectid          => null,
                iv_alias              => c_alias,
                iv_company            => c_company,
                iv_methodcontext      => c_id_path_context_act,
                iv_environment        => c_environment,
                iv_extra_header_name  => l_header_name,
                iv_extra_header_value => l_header_value
            );

            if l_response is null then
                raise_application_error(-20005, 'VL_FN_REST_SERVICES devolvio NULL en Actividades para el proyecto ' || proy.project_id
                );
            elsif l_response = '204' then
                dbms_output.put_line(f_etiqueta_proy(proy.project_id, proy.project_code) || ' CREATE: 0     UPDATE: 0     Sin cambios: 0'
                );

                continue;
            elsif l_response in ( '404', '500', '401' ) then
                raise_application_error(-20006, 'Error al consultar Actividades del proyecto '
                                                || proy.project_id
                                                || ': codigo '
                                                || l_response);
            end if;

            apex_json.parse(l_response);
            l_count := apex_json.get_count(p_path => '.');
            for i in 1..l_count loop
                l_activity_id := apex_json.get_number(
                    p_path => '[%d].activityId',
                    p0     => i
                );
                l_activity_code := utl_i18n.unescape_reference(apex_json.get_varchar2(
                    p_path => '[%d].activityCode',
                    p0     => i
                ));

                l_activity_name := utl_i18n.unescape_reference(apex_json.get_varchar2(
                    p_path => '[%d].activityName',
                    p0     => i
                ));

                l_wbs_id := apex_json.get_number(
                    p_path => '[%d].wbsId',
                    p0     => i
                );
                l_planned_lu := apex_json.get_number(
                    p_path => '[%d].plannedLaborUnits',
                    p0     => i
                );
                l_atcompl_lu := apex_json.get_number(
                    p_path => '[%d].atCompletionLaborUnits',
                    p0     => i
                );

                -- Fechas de baseline del cronograma vivo: se conservan por
                -- trazabilidad. Las fechas OB que se envian a Ecosys NO salen
                -- de aqui, salen de TBL_ACTIVITY_BASELINE.
                l_ob_start := f_iso_to_ts(apex_json.get_varchar2(
                    p_path => '[%d].originalBaselineFields.startDate',
                    p0     => i
                ));

                l_ob_finish := f_iso_to_ts(apex_json.get_varchar2(
                    p_path => '[%d].originalBaselineFields.finishDate',
                    p0     => i
                ));

                l_cb_start := f_iso_to_ts(apex_json.get_varchar2(
                    p_path => '[%d].currentBaselineFields.startDate',
                    p0     => i
                ));

                l_cb_finish := f_iso_to_ts(apex_json.get_varchar2(
                    p_path => '[%d].currentBaselineFields.finishDate',
                    p0     => i
                ));

                -- startDate/finishDate: nunca nulos. Previstas antes de iniciar,
                -- reales despues. Son el origen de las fechas CB (Tendencia).
                l_startdate := f_iso_to_ts(apex_json.get_varchar2(
                    p_path => '[%d].startDate',
                    p0     => i
                ));

                l_finishdate := f_iso_to_ts(apex_json.get_varchar2(
                    p_path => '[%d].finishDate',
                    p0     => i
                ));

                -- El UDF de Status quedo descartado: nunca se creara en OPC.
                -- StatusCO no se envia a Ecosys.
                l_status := null;
                l_updatedate_txt := apex_json.get_varchar2(
                    p_path => '[%d].updateDate',
                    p0     => i
                );
                l_updatedate_ts := f_iso_to_ts(l_updatedate_txt);

                -- Doble validacion contra historico por ACTIVITY_ID
                select
                    max(updatedate)
                into l_max_updatedate_act
                from
                    tbl_activity
                where
                    activity_id = l_activity_id;

                if l_max_updatedate_act is null then
                    l_action := 'CREATE';
                elsif l_updatedate_ts > l_max_updatedate_act then
                    l_action := 'UPDATE';
                else
                    l_total_ignora := l_total_ignora + 1;
                    l_p_ignora := l_p_ignora + 1;
                    continue;
                end if;

                insert into tbl_activity (
                    project_id,
                    wbs_id,
                    activity_id,
                    activity_code,
                    activity_name,
                    planned_labor_units,
                    at_completion_labor_units,
                    original_bl_start_date,
                    original_bl_finish_date,
                    current_bl_start_date,
                    current_bl_finish_date,
                    startdate,
                    finishdate,
                    status,
                    type,
                    updatedate,
                    action
                ) values
                    ( proy.project_id,
                      l_wbs_id,
                      l_activity_id,
                      l_activity_code,
                      l_activity_name,
                      l_planned_lu,
                      l_atcompl_lu,
                      l_ob_start,
                      l_ob_finish,
                      l_cb_start,
                      l_cb_finish,
                      l_startdate,
                      l_finishdate,
                      l_status,
                      'Work Package',
                      l_updatedate_ts,
                      l_action );

                if l_action = 'CREATE' then
                    l_total_create := l_total_create + 1;
                    l_p_create := l_p_create + 1;
                else
                    l_total_update := l_total_update + 1;
                    l_p_update := l_p_update + 1;
                end if;

            end loop;

            dbms_output.put_line(f_etiqueta_proy(proy.project_id, proy.project_code)
                                 || ' CREATE: '
                                 || rpad(l_p_create, 5)
                                 || ' UPDATE: '
                                 || rpad(l_p_update, 5)
                                 || ' Sin cambios: ' || l_p_ignora);

        end loop;

        dbms_output.put_line('Actividades (cronograma) - Proyectos procesados: '
                             || l_proy_procesados
                             || ' | CREATE: '
                             || l_total_create
                             || ' | UPDATE: '
                             || l_total_update
                             || ' | Ignorados (sin cambio real): ' || l_total_ignora);

        commit;
    exception
        when others then
            rollback;
            raise;
    end cargar_actividades;

end pkg_carga_opc;
/

