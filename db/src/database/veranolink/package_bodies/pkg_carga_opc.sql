create or replace package body veranolink.pkg_carga_opc as

    c_id_path_context         constant number := 305; -- endpoint de Proyecto (api/restapi/project, GET) reutilizado
    c_company                 constant varchar2(50) := 'YPF';
    c_environment             constant number := 2;
    c_alias                   constant varchar2(10) := 'OPC';
    c_udf_integracion         constant varchar2(100) := 'YPF | UDF_PRY015_Integración Sequence';
    c_udf_contract_number     constant varchar2(100) := 'YPF | UDF_PRY010_Contrato';

    -- (PATH_CONTEXT = 'api/restapi/wbs/project', tipo GET / ID_VL_CALL_TYPE = 1).
    c_id_path_context_wbs     constant number := 702; 

    -- Endpoint 'View Activities by Project, Code Type, and Code Value'
    -- (PATH_CONTEXT='api/restapi/activity/project', tipo GET / ID_VL_CALL_TYPE=1).
    c_id_path_context_act     constant number := 12;

    -- Filtro de disciplina: solo se cargan las actividades marcadas con 'Obra Civil'
    -- dentro del code type 'YPF | Disciplina' (DSC).
    -- c_codetype_id_disciplina  CONSTANT NUMBER       := 6105;
    -- c_codevalue_disciplina    CONSTANT VARCHAR2(10) := 'OC';

    -- Filtro de fase: solo se cargan las actividades marcadas con 'Construccion'
    c_codetype_id_fase        constant number := 6104;
    c_codevalue_fase          constant varchar2(10) := 'C';

    -- Baselines a incluir en la respuesta (query param del endpoint de OPC).
    c_include_baseline_fields constant varchar2(30) := 'ORIGINAL,CURRENT';

    -- TODO STATUS: cuando se cree el UDF de Status para actividades en OPC,
    --              poner aqui el columnName real y descomentar.
    -- c_udf_status_activity  CONSTANT VARCHAR2(100) := 'YPF | UDF_XXX_Status';

    ------------------------------------------------------------------
    -- F_GET_UDF_VALOR (privada) - sin cambios
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
    -- Convierte una cadena ISO 8601 tipo '2026-03-01T00:00:00' a TIMESTAMP.
    -- Solo toma los primeros 19 caracteres, asi que tolera milisegundos o
    -- timezone al final si algun campo llegara con esos sufijos.
    -- Devuelve NULL si la entrada es NULL o si el formato no puede parsearse.
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
    -- CARGAR_PROYECTOS (v6 - sin cambios respecto a la Ronda 1)
    ------------------------------------------------------------------
    procedure cargar_proyectos is

        type t_foto_rec is record (
                project_id      number,
                contract_number varchar2(50)
        );
        type t_foto_tab is
            table of t_foto_rec index by pls_integer;
        l_foto         t_foto_tab;
        type t_nuevo_rec is record (
                project_id      number,
                project_code    varchar2(60),
                project_name    varchar2(255),
                status          varchar2(20),
                contract_number varchar2(50),
                estado          varchar2(20)
        );
        type t_nuevo_tab is
            table of t_nuevo_rec index by pls_integer;
        l_nuevos       t_nuevo_tab;
        l_token_seed   clob;
        l_response     clob;
        l_count        pls_integer;
        c_filter_url   varchar2(500);
        l_project_id   number;
        l_project_code varchar2(60);
        l_project_name varchar2(255);
        l_status       varchar2(20);
        l_contract_num varchar2(50);
        l_ok           pls_integer := 0;
        l_duplicados   pls_integer := 0;
        l_congelados   pls_integer := 0;
        l_omitidos     pls_integer := 0;
        l_idx          pls_integer := 0;

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

        for i in 1..l_nuevos.count loop
            if l_nuevos(i).estado = 'CONTRATO_CAMBIADO' then
                l_congelados := l_congelados + 1;
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
                    l_nuevos(i).estado          as estado
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
                fecha_carga )
            values
                ( s.project_id,
                  s.project_code,
                  s.project_name,
                  s.status,
                  'Y',
                  s.contract_number,
                  s.estado,
                  systimestamp );

            if l_nuevos(i).estado = 'OK' then
                l_ok := l_ok + 1;
            elsif l_nuevos(i).estado = 'DUPLICADO' then
                l_duplicados := l_duplicados + 1;
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
    -- CARGAR_WBS
    -- Recorre solo los proyectos vigentes hoy y OK, y por cada uno trae
    -- sus WBS de OPC (todas la primera vez; incrementales despues, via el
    -- header 'filters').
    --
    -- DOBLE VALIDACION del updateDate (el header 'filters' es solo una
    -- optimizacion para traer menos datos; la decision real la toma este
    -- codigo):
    --   - Se compara el updateDate que llega contra el MAX(UPDATEDATE) ya
    --     guardado para ese WBS_ID.
    --   - Si el WBS_ID nunca existio          -> INSERT con ACTION='CREATE'.
    --   - Si llega con updateDate MAYOR        -> INSERT con ACTION='UPDATE'.
    --   - Si llega con updateDate MENOR o IGUAL-> se ignora (no se inserta).
    ------------------------------------------------------------------
    procedure cargar_wbs is

        l_token_seed          clob;
        l_response            clob;
        l_count               pls_integer;
        l_max_updatedate_proy timestamp;   -- max del proyecto (para armar el header 'filters')
        l_max_updatedate_wbs  timestamp;   -- max de un WBS_ID puntual (para la doble validacion)
        l_header_name         varchar2(50);
        l_header_value        varchar2(200);
        l_wbs_id              number;
        l_wbs_code            varchar2(60);
        l_wbs_name            varchar2(255);
        l_wbs_path            varchar2(4000);
        l_updatedate_txt      varchar2(50);       -- llega como texto ISO
        l_updatedate_ts       timestamp;          -- ya casteado
        l_action              varchar2(10);
        l_total_create        pls_integer := 0;
        l_total_update        pls_integer := 0;
        l_total_ignora        pls_integer := 0;
        l_proy_procesados     pls_integer := 0;
    begin
        l_token_seed := vl_pkg_rest_services.vl_fn_rest_gettoken(c_alias, c_company, c_environment);

        -- Solo proyectos vigentes HOY y en estado OK
        for proy in (
            select
                project_id
            from
                tbl_project
            where
                    trunc(fecha_carga) = trunc(sysdate)
                and estado_integracion = 'OK'
        ) loop
            l_proy_procesados := l_proy_procesados + 1;

            -- Max updateDate del proyecto -> define si se filtra incremental o se trae todo
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
                -- Optimizacion: pedir a OPC solo lo posterior al ultimo updateDate conocido.
                -- (La exactitud fina no importa: la doble validacion de abajo corrige
                --  cualquier registro de mas que OPC devuelva.)
                l_header_name := 'filters';
                l_header_value := 'updateDate > ' || to_char(l_max_updatedate_proy, 'YYYY-MM-DD"T"HH24:MI:SS');
            end if;

            l_response := vl_pkg_rest_services.vl_fn_rest_services(
                iv_filterurl          => to_char(proy.project_id),
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
                continue;  -- sin contenido, no es error
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
                l_wbs_code := apex_json.get_varchar2(
                    p_path => '[%d].wbsCode',
                    p0     => i
                );
                l_wbs_name := apex_json.get_varchar2(
                    p_path => '[%d].wbsName',
                    p0     => i
                );
                l_wbs_path := apex_json.get_varchar2(
                    p_path => '[%d].wbsPath',
                    p0     => i
                );
                l_updatedate_txt := apex_json.get_varchar2(
                    p_path => '[%d].updateDate',
                    p0     => i
                );

                -- updateDate llega como texto ISO (ej. 2026-07-17T15:49:45); se castea a TIMESTAMP
                l_updatedate_ts := to_timestamp ( replace(l_updatedate_txt, 'T', ' '),
                'YYYY-MM-DD HH24:MI:SS' );

                -- ¿cual es el ultimo updateDate que ya tengo guardado para este WBS_ID?
                select
                    max(updatedate)
                into l_max_updatedate_wbs
                from
                    tbl_wbs
                where
                    wbs_id = l_wbs_id;

                if l_max_updatedate_wbs is null then
                    -- nunca visto -> CREATE
                    l_action := 'CREATE';
                elsif l_updatedate_ts > l_max_updatedate_wbs then
                    -- cambio real -> UPDATE
                    l_action := 'UPDATE';
                else
                    -- mismo o mas viejo -> se ignora (el filtro trajo de mas)
                    l_total_ignora := l_total_ignora + 1;
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
                else
                    l_total_update := l_total_update + 1;
                end if;

            end loop;

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
    -- CARGAR_ACTIVIDADES
    -- Recorre los proyectos vigentes hoy y OK, y por cada uno trae de OPC
    -- solo las actividades con el code 'YPF | Disciplina' = 'Obra Civil'.
    -- El filtrado por disciplina lo hace el servidor (endpoint by codeType
    -- + codeValue), asi que NO recorremos codeValuesActivity en el JSON.
    --
    -- Incremental por proyecto via el header 'filters' (updateDate > MAX
    -- guardado). Doble validacion fila por fila con MAX(UPDATEDATE) por
    -- ACTIVITY_ID para decidir CREATE / UPDATE / ignorar, misma logica
    -- que en cargar_wbs.
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
        l_actual_start        timestamp;
        l_actual_finish       timestamp;
        l_status              varchar2(20);
        l_updatedate_txt      varchar2(50);
        l_updatedate_ts       timestamp;
        l_action              varchar2(10);
        l_baseline            varchar2(10);   -- NUEVO

        l_total_create        pls_integer := 0;
        l_total_update        pls_integer := 0;
        l_total_ignora        pls_integer := 0;
        l_total_sin_lb        pls_integer := 0;   -- NUEVO (solo para consola)
        l_proy_procesados     pls_integer := 0;
    begin
        l_token_seed := vl_pkg_rest_services.vl_fn_rest_gettoken(c_alias, c_company, c_environment);
        for proy in (
            select
                project_id
            from
                tbl_project
            where
                    trunc(fecha_carga) = trunc(sysdate)
                and estado_integracion = 'OK'
        ) loop
            l_proy_procesados := l_proy_procesados + 1;
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
                l_activity_code := apex_json.get_varchar2(
                    p_path => '[%d].activityCode',
                    p0     => i
                );
                l_activity_name := apex_json.get_varchar2(
                    p_path => '[%d].activityName',
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
                l_atcompl_lu := apex_json.get_number(
                    p_path => '[%d].atCompletionLaborUnits',
                    p0     => i
                );
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

                l_actual_start := f_iso_to_ts(apex_json.get_varchar2(
                    p_path => '[%d].actualStart',
                    p0     => i
                ));

                l_actual_finish := f_iso_to_ts(apex_json.get_varchar2(
                    p_path => '[%d].actualFinish',
                    p0     => i
                ));

                -- TODO STATUS: cuando el UDF de status exista en OPC, declarar la constante
                --              c_udf_status_activity y reemplazar la linea 'l_status := NULL'
                --              por la llamada comentada.
                -- l_status := f_get_udf_valor(i, c_udf_status_activity);
                l_status := null;
                l_updatedate_txt := apex_json.get_varchar2(
                    p_path => '[%d].updateDate',
                    p0     => i
                );
                l_updatedate_ts := f_iso_to_ts(l_updatedate_txt);

                -- ============ CALCULO DE BASELINE ============
                -- Reglas:
                --   CURRENT  -> tiene ambas fechas de Current Baseline (sin importar Original)
                --   ORIGINAL -> no tiene CB completo, pero si tiene ambas fechas de Original Baseline
                --   SIN_LB   -> no tiene ninguna de las dos parejas completas
                if
                    l_cb_start is not null
                    and l_cb_finish is not null
                then
                    l_baseline := 'CURRENT';
                elsif
                    l_ob_start is not null
                    and l_ob_finish is not null
                then
                    l_baseline := 'ORIGINAL';
                else
                    l_baseline := 'SIN_LB';
                    l_total_sin_lb := l_total_sin_lb + 1;
                end if;

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
                    actual_start,
                    actual_finish,
                    status,
                    type,
                    updatedate,
                    action,
                    baseline
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
                      l_actual_start,
                      l_actual_finish,
                      l_status,
                      'Work Package',
                      l_updatedate_ts,
                      l_action,
                      l_baseline );

                if l_action = 'CREATE' then
                    l_total_create := l_total_create + 1;
                else
                    l_total_update := l_total_update + 1;
                end if;

            end loop;

        end loop;

        dbms_output.put_line('Actividades - Proyectos procesados: '
                             || l_proy_procesados
                             || ' | CREATE: '
                             || l_total_create
                             || ' | UPDATE: '
                             || l_total_update
                             || ' | Ignorados (sin cambio real): '
                             || l_total_ignora
                             || ' | SIN_LB (no en ninguna baseline): ' || l_total_sin_lb);

        commit;
    exception
        when others then
            rollback;
            raise;
    end cargar_actividades;

end pkg_carga_opc;
/


-- sqlcl_snapshot {"hash":"8dc62bf5e30fa21657b5c2c3addb47d6d5327284","type":"PACKAGE_BODY","name":"PKG_CARGA_OPC","schemaName":"VERANOLINK","sxml":""}