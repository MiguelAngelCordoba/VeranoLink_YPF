create or replace package body veranolink.pkg_envio_sequence as

    c_company             constant varchar2(50) := 'YPF';
    c_environment         constant number := fn_ambiente;
    c_endpoint_crear      constant varchar2(100) := 'CrearActividad/?ContractID=';
    -- : el Postman usa 'ActualizarActividad/?ContractID='.
    --              Si el envio falla con 404, agregar la barra antes del '?'.
    c_endpoint_actualizar constant varchar2(100) := 'ActualizarActividad/?ContractID=';

    -- Tipo para acumular los metadatos del lote en paralelo al payload
    type t_meta_rec is record (
            object_id   number,
            object_code varchar2(60),
            object_name varchar2(255),
            hier_path   varchar2(4000),
            baseline_id number,
            tipo_objeto varchar2(10),
            update_date varchar2(30)
    );
    type t_meta_tab is
        table of t_meta_rec index by pls_integer;

    ------------------------------------------------------------------
        ------------------------------------------------------------------
    -- INS_LOTE
    -- Una fila por peticion HTTP. Aisla los CLOB de request/response,
    -- que antes se repetian identicos en cada fila de LOG_OPC_SEQUENCE
    -- (un lote de 380 objetos guardaba 380 copias del mismo payload).
    -- Transaccion autonoma: debe existir antes de registrar los objetos.
    ------------------------------------------------------------------
    procedure ins_lote (
        p_project_id      in number,
        p_contract_number in varchar2,
        p_tipo_objeto     in varchar2,
        p_accion          in varchar2,
        p_resultado       in varchar2,
        p_http_status     in number,
        p_total_objetos   in number,
        p_total_ok        in number,
        p_total_fallo     in number,
        p_mensaje         in clob,
        p_payload         in clob,
        po_id_lote        out number
    ) is
        pragma autonomous_transaction;
    begin
        insert into log_lote (
            project_id,
            contract_number,
            tipo_objeto,
            accion,
            fecha_ejecucion,
            resultado,
            http_status,
            total_objetos,
            total_ok,
            total_fallo,
            mensaje_respuesta,
            payload_enviado
        ) values
            ( p_project_id,
              p_contract_number,
              p_tipo_objeto,
              p_accion,
              systimestamp,
              p_resultado,
              p_http_status,
              p_total_objetos,
              p_total_ok,
              p_total_fallo,
              p_mensaje,
              p_payload )
        returning id_lote into po_id_lote;

        commit;
    end ins_lote;

    ------------------------------------------------------------------
    -- INS_LOG
    -- Una fila por objeto. Es el ancla de sincronizacion: de RESULTADO,
    -- ACCION y FECHA_EJECUCION dependen las vistas de creacion y
    -- actualizacion y los reintentos. Los CLOB viven en LOG_LOTE.
    -- Transaccion autonoma: el log se conserva aunque el proceso
    -- principal haga rollback.
    ------------------------------------------------------------------
    procedure ins_log (
        p_project_id      in number,
        p_contract_number in varchar2,
        p_tipo_objeto     in varchar2,
        p_object_id       in number,
        p_object_code     in varchar2,
        p_object_name     in varchar2,
        p_hierarchy_path  in varchar2,
        p_baseline_id     in number,
        p_update_sinc     in timestamp,
        p_accion          in varchar2,
        p_resultado       in varchar2,
        p_id_lote         in number
    ) is
        pragma autonomous_transaction;
    begin
        insert into log_opc_sequence (
            project_id,
            contract_number,
            tipo_objeto,
            object_id,
            object_code,
            object_name,
            hierarchy_path_id,
            project_baseline_id,
            update_sincronizado,
            accion,
            fecha_ejecucion,
            resultado,
            id_lote
        ) values
            ( p_project_id,
              p_contract_number,
              p_tipo_objeto,
              p_object_id,
              p_object_code,
              p_object_name,
              p_hierarchy_path,
              p_baseline_id,
              p_update_sinc,
              p_accion,
              systimestamp,
              p_resultado,
              p_id_lote );

        commit;
    end ins_log;

    ------------------------------------------------------------------
    -- ENVIAR_LOTE (generica: sirve para creacion y actualizacion)
    -- Recibe endpoint, metodo HTTP y accion a registrar.
    --
    -- CLAVE DEL LOG EN ACTUALIZACION: se guarda el OBJECT_CODE que quedo
    -- en Ecosys tras el envio. Si el payload traia CostObjectID nuevo, ese
    -- es el que se guarda; si no, se conserva el anterior. De ese codigo
    -- depende la derivacion del path vigente en VIEW_SEQUENCE_UPDATE.
    ------------------------------------------------------------------
    procedure enviar_lote (
        p_project_id      in number,
        p_contract_number in varchar2,
        p_endpoint        in varchar2,
        p_http_method     in varchar2,
        p_accion          in varchar2,
        p_meta            in t_meta_tab,
        p_payload_lote    in clob,
        po_ok             out pls_integer,
        po_fallo          out pls_integer
    ) is
        -- Indice externalId -> posicion. Evita recorrer toda la coleccion
        -- por cada resultado devuelto (busqueda directa en lugar de barrido).
        type t_idx_tab is
            table of pls_integer index by varchar2(50);
        l_idx_ext      t_idx_tab;
        l_procesados   t_idx_tab;
        l_url          varchar2(2000);
        l_auth         varchar2(1000);
        l_response     clob;
        l_http_status  number;
        l_count        pls_integer;
        l_ext_id_txt   varchar2(50);
        l_success_flag varchar2(10);
        l_resultado    varchar2(10);
        l_idx          pls_integer;
        l_update_ts    timestamp;
        l_id_lote      number;
        l_tipo_lote    varchar2(10);
        l_res_lote     varchar2(10);
        l_tiene_wbs    boolean := false;
        l_tiene_act    boolean := false;

        function f_ts (
            p_txt varchar2
        ) return timestamp is
        begin
            if p_txt is null then
                return null;
            end if;
            return to_timestamp ( replace(
                substr(p_txt, 1, 19),
                'T',
                ' '
            ),
            'YYYY-MM-DD HH24:MI:SS' );

        exception
            when others then
                return null;
        end f_ts;

    begin
        po_ok := 0;
        po_fallo := 0;
        if p_meta.count = 0 then
            return;
        end if;
        for i in 1..p_meta.count loop
            l_idx_ext(to_char(p_meta(i).object_id)) := i;
            if p_meta(i).tipo_objeto = 'WBS' then
                l_tiene_wbs := true;
            else
                l_tiene_act := true;
            end if;

        end loop;

        -- En actualizacion WBS y actividades viajan en la misma peticion,
        -- por lo que un lote puede ser MIXTO.
        l_tipo_lote :=
            case
                when l_tiene_wbs
                     and l_tiene_act then
                    'MIXTO'
                when l_tiene_wbs then
                    'WBS'
                else
                    'ACTIVITY'
            end;
        select
            source_url,
            source_authentication
        into
            l_url,
            l_auth
        from
            vl_sequence_sources
        where
                company = c_company
            and environment = c_environment;

        l_url := l_url
                 || p_endpoint
                 || p_contract_number;
        apex_web_service.g_request_headers.delete();
        apex_web_service.g_request_headers(1).name := 'Authorization';
        apex_web_service.g_request_headers(1).value := 'Basic ' || l_auth;
        apex_web_service.g_request_headers(2).name := 'Content-Type';
        apex_web_service.g_request_headers(2).value := 'application/json';
        l_response := apex_web_service.make_rest_request(
            p_url         => l_url,
            p_http_method => p_http_method,
            p_body        => p_payload_lote
        );

        l_http_status := apex_web_service.g_status_code;

        -- Fallo de transporte o autenticacion: la respuesta puede ser HTML.
        -- No se intenta parsear JSON. Todo el lote se marca como fallido.
        if l_http_status not in ( 200, 201 ) then
            ins_lote(
                p_project_id      => p_project_id,
                p_contract_number => p_contract_number,
                p_tipo_objeto     => l_tipo_lote,
                p_accion          => p_accion,
                p_resultado       => 'FALLO',
                p_http_status     => l_http_status,
                p_total_objetos   => p_meta.count,
                p_total_ok        => 0,
                p_total_fallo     => p_meta.count,
                p_mensaje         => l_response,
                p_payload         => p_payload_lote,
                po_id_lote        => l_id_lote
            );

            for i in 1..p_meta.count loop
                ins_log(
                    p_project_id      => p_project_id,
                    p_contract_number => p_contract_number,
                    p_tipo_objeto     => p_meta(i).tipo_objeto,
                    p_object_id       => p_meta(i).object_id,
                    p_object_code     => p_meta(i).object_code,
                    p_object_name     => p_meta(i).object_name,
                    p_hierarchy_path  => p_meta(i).hier_path,
                    p_baseline_id     => p_meta(i).baseline_id,
                    p_update_sinc     => f_ts(p_meta(i).update_date),
                    p_accion          => p_accion,
                    p_resultado       => 'FALLO',
                    p_id_lote         => l_id_lote
                );

                po_fallo := po_fallo + 1;
            end loop;

            return;
        end if;

        apex_json.parse(l_response);
        l_count := apex_json.get_count(p_path => 'UpdateStatuses');

        -- Primera pasada: se cuentan exitos y fallos SIN escribir log, porque
        -- el RESULTADO del lote (OK / PARCIAL / FALLO) solo se conoce al final
        -- y la fila de LOG_LOTE debe existir antes de referenciarla.
        for i in 1..nvl(l_count, 0) loop
            l_ext_id_txt := apex_json.get_varchar2(
                p_path => 'UpdateStatuses[%d].externalId',
                p0     => i
            );
            l_success_flag := apex_json.get_varchar2(
                p_path => 'UpdateStatuses[%d].successFlag',
                p0     => i
            );
            if not l_idx_ext.exists(l_ext_id_txt) then
                continue;
            end if;

            -- HTTP 200 NO implica exito: manda successFlag.
            if lower(l_success_flag) = 'true' then
                po_ok := po_ok + 1;
            else
                po_fallo := po_fallo + 1;
            end if;

            l_procesados(l_ext_id_txt) := l_idx_ext(l_ext_id_txt);
        end loop;

        -- Objetos enviados sin status de respuesta: cuentan como fallo.
        for i in 1..p_meta.count loop
            if not l_procesados.exists(to_char(p_meta(i).object_id)) then
                po_fallo := po_fallo + 1;
            end if;
        end loop;

        l_res_lote :=
            case
                when po_fallo = 0 then
                    'OK'
                when po_ok = 0    then
                    'FALLO'
                else
                    'PARCIAL'
            end;

        ins_lote(
            p_project_id      => p_project_id,
            p_contract_number => p_contract_number,
            p_tipo_objeto     => l_tipo_lote,
            p_accion          => p_accion,
            p_resultado       => l_res_lote,
            p_http_status     => l_http_status,
            p_total_objetos   => p_meta.count,
            p_total_ok        => po_ok,
            p_total_fallo     => po_fallo,
            p_mensaje         => l_response,
            p_payload         => p_payload_lote,
            po_id_lote        => l_id_lote
        );

        -- Segunda pasada: ya con el ID_LOTE, se escribe una fila por objeto.
        l_procesados.delete;
        for i in 1..nvl(l_count, 0) loop
            l_ext_id_txt := apex_json.get_varchar2(
                p_path => 'UpdateStatuses[%d].externalId',
                p0     => i
            );
            l_success_flag := apex_json.get_varchar2(
                p_path => 'UpdateStatuses[%d].successFlag',
                p0     => i
            );
            if l_idx_ext.exists(l_ext_id_txt) then
                l_idx := l_idx_ext(l_ext_id_txt);
            else
                continue;
            end if;

            l_resultado :=
                case
                    when lower(l_success_flag) = 'true' then
                        'OK'
                    else
                        'FALLO'
                end;
            ins_log(
                p_project_id      => p_project_id,
                p_contract_number => p_contract_number,
                p_tipo_objeto     => p_meta(l_idx).tipo_objeto,
                p_object_id       => p_meta(l_idx).object_id,
                p_object_code     => p_meta(l_idx).object_code,
                p_object_name     => p_meta(l_idx).object_name,
                p_hierarchy_path  => p_meta(l_idx).hier_path,
                p_baseline_id     => p_meta(l_idx).baseline_id,
                p_update_sinc     => f_ts(p_meta(l_idx).update_date),
                p_accion          => p_accion,
                p_resultado       => l_resultado,
                p_id_lote         => l_id_lote
            );

            l_procesados(l_ext_id_txt) := l_idx;
        end loop;

        -- Objetos enviados sin status de respuesta: se registran como FALLO
        -- para no perderlos del seguimiento.
        for i in 1..p_meta.count loop
            if not l_procesados.exists(to_char(p_meta(i).object_id)) then
                ins_log(
                    p_project_id      => p_project_id,
                    p_contract_number => p_contract_number,
                    p_tipo_objeto     => p_meta(i).tipo_objeto,
                    p_object_id       => p_meta(i).object_id,
                    p_object_code     => p_meta(i).object_code,
                    p_object_name     => p_meta(i).object_name,
                    p_hierarchy_path  => p_meta(i).hier_path,
                    p_baseline_id     => p_meta(i).baseline_id,
                    p_update_sinc     => f_ts(p_meta(i).update_date),
                    p_accion          => p_accion,
                    p_resultado       => 'FALLO',
                    p_id_lote         => l_id_lote
                );

            end if;
        end loop;

    exception
        when others then
            po_ok := 0;
            po_fallo := p_meta.count;
            ins_lote(
                p_project_id      => p_project_id,
                p_contract_number => p_contract_number,
                p_tipo_objeto     => l_tipo_lote,
                p_accion          => p_accion,
                p_resultado       => 'FALLO',
                p_http_status     => nvl(l_http_status, -1),
                p_total_objetos   => p_meta.count,
                p_total_ok        => 0,
                p_total_fallo     => p_meta.count,
                p_mensaje         => 'EXCEPCION: ' || sqlerrm,
                p_payload         => p_payload_lote,
                po_id_lote        => l_id_lote
            );

            for i in 1..p_meta.count loop
                ins_log(
                    p_project_id      => p_project_id,
                    p_contract_number => p_contract_number,
                    p_tipo_objeto     => p_meta(i).tipo_objeto,
                    p_object_id       => p_meta(i).object_id,
                    p_object_code     => p_meta(i).object_code,
                    p_object_name     => p_meta(i).object_name,
                    p_hierarchy_path  => p_meta(i).hier_path,
                    p_baseline_id     => p_meta(i).baseline_id,
                    p_update_sinc     => f_ts(p_meta(i).update_date),
                    p_accion          => p_accion,
                    p_resultado       => 'FALLO',
                    p_id_lote         => l_id_lote
                );
            end loop;

    end enviar_lote;

    ------------------------------------------------------------------
    -- ENVIAR_CREACION
    -- Por proyecto: lote de WBS (orden jerarquico) y lote de actividades.
    -- Son DOS peticiones separadas porque el padre debe existir en Ecosys
    -- antes de crear al hijo.
    ------------------------------------------------------------------
    procedure enviar_creacion is

        l_payload   clob;
        l_meta      t_meta_tab;
        l_n         pls_integer;
        l_ok        pls_integer;
        l_fallo     pls_integer;
        l_tot_ok    pls_integer := 0;
        l_tot_fallo pls_integer := 0;
        l_lotes     pls_integer := 0;
        l_txt       varchar2(32767);
    begin
        for proy in (
            select distinct
                project_id,
                contract_number
            from
                view_sequence_create
            order by
                project_id
        ) loop
            for tipo in (
                select
                    'WBS' as t
                from
                    dual
                union all
                select
                    'ACTIVITY'
                from
                    dual
            ) loop
                l_meta.delete;
                l_n := 0;
                if dbms_lob.istemporary(l_payload) = 1 then
                    dbms_lob.freetemporary(l_payload);
                end if;

                dbms_lob.createtemporary(l_payload, true);
                for r in (
                    select
                        "ExternalID"                                          as ext_id,
                        "CostObjectID"                                        as cost_code,
                        "CostObjectName"                                      as cost_name,
                        "HierarchyPathID"                                     as hpath,
                        project_baseline_id                                   as bl_id,
                        tipo_objeto,
                        to_char(updatedate_actual, 'YYYY-MM-DD"T"HH24:MI:SS') as upd,
                        payload_json
                    from
                        view_sequence_create
                    where
                            project_id = proy.project_id
                        and tipo_objeto = tipo.t
                     -- Los padres se crean antes que los hijos
                    order by
                        orden_jerarquico,
                        "HierarchyPathID"
                ) loop
                    l_n := l_n + 1;
                    l_meta(l_n).object_id := to_number ( r.ext_id );
                    l_meta(l_n).object_code := r.cost_code;
                    l_meta(l_n).object_name := r.cost_name;
                    l_meta(l_n).hier_path := r.hpath;
                    l_meta(l_n).baseline_id := r.bl_id;
                    l_meta(l_n).tipo_objeto := r.tipo_objeto;
                    l_meta(l_n).update_date := r.upd;

                    -- WRITEAPPEND en lugar de ||: concatenar CLOB copia todo
                    -- el acumulado en cada vuelta (costo cuadratico).
                    l_txt :=
                        case
                            when l_n = 1 then
                                '['
                            else
                                ','
                        end
                        || r.payload_json;

                    dbms_lob.writeappend(l_payload,
                                         length(l_txt),
                                         l_txt);
                end loop;

                if l_n > 0 then
                    dbms_lob.writeappend(l_payload, 1, ']');
                    l_lotes := l_lotes + 1;
                    enviar_lote(
                        p_project_id      => proy.project_id,
                        p_contract_number => proy.contract_number,
                        p_endpoint        => c_endpoint_crear,
                        p_http_method     => 'PUT',
                        p_accion          => 'CREATE',
                        p_meta            => l_meta,
                        p_payload_lote    => l_payload,
                        po_ok             => l_ok,
                        po_fallo          => l_fallo
                    );

                    l_tot_ok := l_tot_ok + l_ok;
                    l_tot_fallo := l_tot_fallo + l_fallo;
                    dbms_output.put_line('Proyecto '
                                         || proy.project_id
                                         || ' | CREATE '
                                         || rpad(tipo.t, 8)
                                         || ' | OK: '
                                         || l_ok
                                         || ' | FALLO: ' || l_fallo);

                end if;

            end loop;
        end loop;

        if dbms_lob.istemporary(l_payload) = 1 then
            dbms_lob.freetemporary(l_payload);
        end if;

        dbms_output.put_line('-----------------------------------------------------');
        dbms_output.put_line('CREACION - Lotes: '
                             || l_lotes
                             || ' | OK: '
                             || l_tot_ok
                             || ' | FALLO: ' || l_tot_fallo);

    end enviar_creacion;

    ------------------------------------------------------------------
    -- ENVIAR_ACTUALIZACION
    -- Por proyecto: UNA SOLA peticion con WBS y actividades juntas.
    --
    -- POR QUE UNA SOLA: Ecosys resuelve los paths de TODAS las filas del
    -- array contra el estado que existia ANTES del request. Si se separara
    -- en dos peticiones, la segunda arrancaria con los WBS ya renombrados y
    -- habria que recalcular los paths de las actividades. Yendo todo junto,
    -- cada objeto viaja con su path anterior al cambio y Ecosys propaga
    -- internamente el renombrado a los descendientes.
    --
    -- El orden (WBS por nivel, luego actividades) se mantiene por seguridad.
    ------------------------------------------------------------------
    procedure enviar_actualizacion is

        l_payload   clob;
        l_meta      t_meta_tab;
        l_n         pls_integer;
        l_ok        pls_integer;
        l_fallo     pls_integer;
        l_tot_ok    pls_integer := 0;
        l_tot_fallo pls_integer := 0;
        l_lotes     pls_integer := 0;
        l_txt       varchar2(32767);
    begin
        for proy in (
            select distinct
                project_id,
                contract_number
            from
                view_sequence_update
            order by
                project_id
        ) loop
            l_meta.delete;
            l_n := 0;
            if dbms_lob.istemporary(l_payload) = 1 then
                dbms_lob.freetemporary(l_payload);
            end if;

            dbms_lob.createtemporary(l_payload, true);
            for r in (
                select
                    "ExternalID"                                          as ext_id,
                    "CostObjectID"                                        as cost_code,
                    "CostObjectName"                                      as cost_name,
                    "HierarchyPathID"                                     as hpath,
                    project_baseline_id                                   as bl_id,
                    tipo_objeto,
                    motivo,
                    to_char(updatedate_actual, 'YYYY-MM-DD"T"HH24:MI:SS') as upd,
                    payload_json
                from
                    view_sequence_update
                where
                    project_id = proy.project_id
                 -- WBS de menor a mayor nivel, actividades al final (9999)
                order by
                    orden_jerarquico,
                    "HierarchyPathID"
            ) loop
                l_n := l_n + 1;
                l_meta(l_n).object_id := to_number ( r.ext_id );
                -- Si el payload no traia codigo nuevo (no cambio), se conserva
                -- el que ya estaba sincronizado: el log debe reflejar SIEMPRE
                -- el codigo real en Ecosys, del que depende la derivacion del path.
                l_meta(l_n).object_code := nvl(r.cost_code,
                                               substr(r.hpath,
                                                      instr(r.hpath, '.', -1) + 1));

                l_meta(l_n).object_name := r.cost_name;
                l_meta(l_n).hier_path := r.hpath;
                l_meta(l_n).baseline_id := r.bl_id;
                l_meta(l_n).tipo_objeto := r.tipo_objeto;
                l_meta(l_n).update_date := r.upd;
                l_txt :=
                    case
                        when l_n = 1 then
                            '['
                        else
                            ','
                    end
                    || r.payload_json;

                dbms_lob.writeappend(l_payload,
                                     length(l_txt),
                                     l_txt);
            end loop;

            if l_n > 0 then
                dbms_lob.writeappend(l_payload, 1, ']');
                l_lotes := l_lotes + 1;
                enviar_lote(
                    p_project_id      => proy.project_id,
                    p_contract_number => proy.contract_number,
                    p_endpoint        => c_endpoint_actualizar,
                    p_http_method     => 'POST',
                    p_accion          => 'UPDATE',
                    p_meta            => l_meta,
                    p_payload_lote    => l_payload,
                    po_ok             => l_ok,
                    po_fallo          => l_fallo
                );

                l_tot_ok := l_tot_ok + l_ok;
                l_tot_fallo := l_tot_fallo + l_fallo;
                dbms_output.put_line('Proyecto '
                                     || proy.project_id
                                     || ' | UPDATE          | OK: '
                                     || l_ok
                                     || ' | FALLO: ' || l_fallo);

            end if;

        end loop;

        if dbms_lob.istemporary(l_payload) = 1 then
            dbms_lob.freetemporary(l_payload);
        end if;

        dbms_output.put_line('-----------------------------------------------------');
        dbms_output.put_line('ACTUALIZACION - Lotes: '
                             || l_lotes
                             || ' | OK: '
                             || l_tot_ok
                             || ' | FALLO: ' || l_tot_fallo);

    end enviar_actualizacion;

    ------------------------------------------------------------------
    -- INTEGRACION_DIARIA
    -- Orden y dependencias:
    --   cargar_proyectos            -> marca los proyectos vigentes del dia
    --   cargar_wbs                  -> estructura jerarquica (la necesita el paso siguiente)
    --   cargar_baselines            -> gate: que LB esta vigente por proyecto
    --   cargar_actividades_baseline -> fuente de CREACION (usa TBL_WBS.WBS_PATH)
    --   cargar_actividades          -> fuente de ACTUALIZACION (cronograma actual)
    --   enviar_creacion             -> crea lo que no existe en Ecosys
    --   enviar_actualizacion        -> actualiza lo que ya existe y cambio
    --
    -- enviar_creacion va antes que enviar_actualizacion: un objeto recien
    -- creado no debe entrar al flujo de update en la misma corrida (la vista
    -- de update exige un envio OK previo, asi que se excluye solo).
    --
    -- Si un paso falla se propaga la excepcion, el scheduler marca el job
    -- como FAILED y los pasos siguientes NO se ejecutan.
    ------------------------------------------------------------------
    procedure integracion_diaria is
        l_inicio timestamp := systimestamp;
        l_paso   varchar2(50);
        l_cnt    pls_integer;
    begin
        dbms_output.put_line('=== Inicio integracion diaria: '
                             || to_char(l_inicio, 'YYYY-MM-DD HH24:MI:SS') || ' ===');
        l_paso := 'cargar_workspaces';
        dbms_output.put_line('>>> ' || l_paso);
        pkg_carga_opc.cargar_workspaces;
        l_paso := 'cargar_proyectos';
        dbms_output.put_line('>>> ' || l_paso);
        pkg_carga_opc.cargar_proyectos;
        l_paso := 'cargar_wbs';
        dbms_output.put_line('>>> ' || l_paso);
        pkg_carga_opc.cargar_wbs;
        l_paso := 'cargar_baselines';
        dbms_output.put_line('>>> ' || l_paso);
        pkg_carga_opc.cargar_baselines;
        l_paso := 'cargar_actividades_baseline';
        dbms_output.put_line('>>> ' || l_paso);
        pkg_carga_opc.cargar_actividades_baseline;
        l_paso := 'cargar_actividades';
        dbms_output.put_line('>>> ' || l_paso);
        pkg_carga_opc.cargar_actividades;
        l_paso := 'enviar_creacion';
        dbms_output.put_line('>>> ' || l_paso);
        enviar_creacion;
        l_paso := 'enviar_actualizacion';
        dbms_output.put_line('>>> ' || l_paso);
        enviar_actualizacion;

        -- REINTENTO DE CREACION (una sola vez).
        -- enviar_creacion es idempotente: VIEW_SEQUENCE_CREATE solo trae objetos sin
        -- registro OK, de modo que el reintento envia unicamente lo que quedo pendiente.
        select
            count(*)
        into l_cnt
        from
            log_opc_sequence
        where
                accion = 'CREATE'
            and resultado = 'FALLO'
            and fecha_ejecucion >= l_inicio;

        if l_cnt > 0 then
            l_paso := 'reintento_creacion';
            dbms_output.put_line('>>> '
                                 || l_paso
                                 || ' ('
                                 || l_cnt || ' fallos de creacion en esta corrida)');

            enviar_creacion;
        end if;

        -- Mantenimiento: se purgan los lotes viejos de auditoria.
        -- Va al final para que un fallo de purga nunca comprometa la
        -- integracion, que ya termino su trabajo real en este punto.
        l_paso := 'purgar_log_lote';
        begin
            purgar_log_lote(60); -- 60 dias para depurar, cambiar el maximo de dias aqui de ser necesario
        exception
            when others then
                dbms_output.put_line('!!! Purga de LOG_LOTE fallida (no bloquea): ' || sqlerrm);
        end;

        dbms_output.put_line('=== Fin integracion diaria: '
                             || to_char(systimestamp, 'YYYY-MM-DD HH24:MI:SS') || ' ===');
    exception
        when others then
            dbms_output.put_line('!!! FALLO en paso: ' || l_paso);
            dbms_output.put_line('!!! Error: ' || sqlerrm);
            raise;
    end integracion_diaria;

    ------------------------------------------------------------------
    -- PURGAR_LOG_LOTE
    -- Elimina lotes anteriores a p_dias. LOG_LOTE guarda los CLOB de
    -- request y response, que son con diferencia lo mas pesado del
    -- esquema, y su valor de diagnostico expira a los pocos dias.
    --
    -- Se borra en tandas para no generar una transaccion enorme de undo
    -- con CLOB. El DELETE libera espacio para reuso pero NO reduce el
    -- segmento: para devolver espacio al tablespace hace falta un SHRINK
    -- manual, que es mantenimiento ocasional y no parte del job.
    --
    -- Las filas de LOG_OPC_SEQUENCE del lote purgado conservan su
    -- ID_LOTE aunque ya no exista: no hay FK y sirve para saber que
    -- pertenecieron al mismo envio, aunque el payload ya expiro.
    ------------------------------------------------------------------
    procedure purgar_log_lote (
        p_dias in number default 60
    ) is
        l_borradas pls_integer := 0;
        l_ciclo    pls_integer;
    begin
        loop
            delete from log_lote
            where
                    fecha_ejecucion < systimestamp - numtodsinterval(p_dias, 'DAY')
                and rownum <= 500;

            l_ciclo := sql%rowcount;
            l_borradas := l_borradas + l_ciclo;
            commit;
            exit when l_ciclo = 0;
        end loop;

        if l_borradas > 0 then
            dbms_output.put_line('Purga LOG_LOTE: '
                                 || l_borradas
                                 || ' lotes eliminados (anteriores a '
                                 || p_dias || ' dias).');

        end if;

    end purgar_log_lote;

end pkg_envio_sequence;
/


-- sqlcl_snapshot {"hash":"1918e04359f2e39c2ff6e21dbf8ad06e29cc5bd6","type":"PACKAGE_BODY","name":"PKG_ENVIO_SEQUENCE","schemaName":"VERANOLINK","sxml":""}