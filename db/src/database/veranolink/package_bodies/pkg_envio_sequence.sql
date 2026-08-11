create or replace package body veranolink.pkg_envio_sequence as

    c_company        constant varchar2(50) := 'YPF';
    c_environment    constant number := 2;
    c_endpoint_crear constant varchar2(100) := 'CrearActividad?ContractID=';

    procedure ins_log (
        p_project_id      in number,
        p_contract_number in varchar2,
        p_tipo_objeto     in varchar2,
        p_object_id       in number,
        p_object_code     in varchar2,
        p_object_name     in varchar2,
        p_update_sinc     in timestamp,
        p_accion          in varchar2,
        p_resultado       in varchar2,
        p_http_status     in number,
        p_mensaje         in clob,
        p_payload         in clob
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
            update_sincronizado,
            accion,
            fecha_ejecucion,
            resultado,
            http_status,
            mensaje_respuesta,
            payload_enviado
        ) values
            ( p_project_id,
              p_contract_number,
              p_tipo_objeto,
              p_object_id,
              p_object_code,
              p_object_name,
              p_update_sinc,
              p_accion,
              systimestamp,
              p_resultado,
              p_http_status,
              p_mensaje,
              p_payload );

        commit;
    end ins_log;

    procedure enviar_lote (
        p_project_id      in number,
        p_contract_number in varchar2,
        p_tipo_objeto     in varchar2,
        p_object_ids      in sys.odcinumberlist,
        p_object_codes    in sys.odcivarchar2list,
        p_object_names    in sys.odcivarchar2list,
        p_update_dates    in sys.odcivarchar2list,
        p_payload_lote    in clob,
        po_ok             out pls_integer,
        po_fallo          out pls_integer
    ) is

        l_url          varchar2(2000);
        l_auth         varchar2(1000);
        l_response     clob;
        l_http_status  number;
        l_count        pls_integer;
        l_ext_id_txt   varchar2(50);
        l_ext_id       number;
        l_success_flag varchar2(10);
        l_resultado    varchar2(10);
        l_idx          pls_integer;
        l_update_ts    timestamp;
    begin
        po_ok := 0;
        po_fallo := 0;
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
                 || c_endpoint_crear
                 || p_contract_number;
        apex_web_service.g_request_headers.delete();
        apex_web_service.g_request_headers(1).name := 'Authorization';
        apex_web_service.g_request_headers(1).value := 'Basic ' || l_auth;
        apex_web_service.g_request_headers(2).name := 'Content-Type';
        apex_web_service.g_request_headers(2).value := 'application/json';
        l_response := apex_web_service.make_rest_request(
            p_url         => l_url,
            p_http_method => 'PUT',
            p_body        => p_payload_lote
        );

        l_http_status := apex_web_service.g_status_code;
        if l_http_status not in ( 200, 201 ) then
            for i in 1..p_object_ids.count loop
                l_update_ts := to_timestamp ( replace(
                    substr(
                        p_update_dates(i),
                        1,
                        19
                    ),
                    'T',
                    ' '
                ),
                'YYYY-MM-DD HH24:MI:SS' );

                ins_log(
                    p_project_id      => p_project_id,
                    p_contract_number => p_contract_number,
                    p_tipo_objeto     => p_tipo_objeto,
                    p_object_id       => p_object_ids(i),
                    p_object_code     => p_object_codes(i),
                    p_object_name     => p_object_names(i),
                    p_update_sinc     => l_update_ts,
                    p_accion          => 'CREATE',
                    p_resultado       => 'FALLO',
                    p_http_status     => l_http_status,
                    p_mensaje         => l_response,
                    p_payload         => p_payload_lote
                );

                po_fallo := po_fallo + 1;
            end loop;

            return;
        end if;

        apex_json.parse(l_response);
        l_count := apex_json.get_count(p_path => 'UpdateStatuses');
        for i in 1..nvl(l_count, 0) loop
            l_ext_id_txt := apex_json.get_varchar2(
                p_path => 'UpdateStatuses[%d].externalId',
                p0     => i
            );
            l_success_flag := apex_json.get_varchar2(
                p_path => 'UpdateStatuses[%d].successFlag',
                p0     => i
            );
            begin
                l_ext_id := to_number ( l_ext_id_txt );
            exception
                when others then
                    l_ext_id := null;
            end;

            l_idx := null;
            for j in 1..p_object_ids.count loop
                if p_object_ids(j) = l_ext_id then
                    l_idx := j;
                    exit;
                end if;
            end loop;

            if l_idx is null then
                continue;
            end if;
            if lower(l_success_flag) = 'true' then
                l_resultado := 'OK';
                po_ok := po_ok + 1;
            else
                l_resultado := 'FALLO';
                po_fallo := po_fallo + 1;
            end if;

            l_update_ts := to_timestamp ( replace(
                substr(
                    p_update_dates(l_idx),
                    1,
                    19
                ),
                'T',
                ' '
            ),
            'YYYY-MM-DD HH24:MI:SS' );

            ins_log(
                p_project_id      => p_project_id,
                p_contract_number => p_contract_number,
                p_tipo_objeto     => p_tipo_objeto,
                p_object_id       => p_object_ids(l_idx),
                p_object_code     => p_object_codes(l_idx),
                p_object_name     => p_object_names(l_idx),
                p_update_sinc     => l_update_ts,
                p_accion          => 'CREATE',
                p_resultado       => l_resultado,
                p_http_status     => l_http_status,
                p_mensaje         => l_response,
                p_payload         => p_payload_lote
            );

        end loop;

    exception
        when others then
            for i in 1..p_object_ids.count loop
                begin
                    l_update_ts := to_timestamp ( replace(
                        substr(
                            p_update_dates(i),
                            1,
                            19
                        ),
                        'T',
                        ' '
                    ),
                    'YYYY-MM-DD HH24:MI:SS' );
                exception
                    when others then
                        l_update_ts := null;
                end;

                ins_log(
                    p_project_id      => p_project_id,
                    p_contract_number => p_contract_number,
                    p_tipo_objeto     => p_tipo_objeto,
                    p_object_id       => p_object_ids(i),
                    p_object_code     => p_object_codes(i),
                    p_object_name     => p_object_names(i),
                    p_update_sinc     => l_update_ts,
                    p_accion          => 'CREATE',
                    p_resultado       => 'FALLO',
                    p_http_status     => nvl(l_http_status, -1),
                    p_mensaje         => 'EXCEPCION: ' || sqlerrm,
                    p_payload         => p_payload_lote
                );

                po_fallo := po_fallo + 1;
            end loop;
    end enviar_lote;

    procedure enviar_creacion is

        l_payload_lote   clob;
        l_object_ids     sys.odcinumberlist;
        l_object_codes   sys.odcivarchar2list;
        l_object_names   sys.odcivarchar2list;
        l_update_dates   sys.odcivarchar2list;
        l_ok             pls_integer;
        l_fallo          pls_integer;
        l_tot_ok         pls_integer := 0;
        l_tot_fallo      pls_integer := 0;
        l_lotes_enviados pls_integer := 0;
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

            -- ============= LOTE 1: WBS =============
            l_object_ids := sys.odcinumberlist();
            l_object_codes := sys.odcivarchar2list();
            l_object_names := sys.odcivarchar2list();
            l_update_dates := sys.odcivarchar2list();
            l_payload_lote := null;
            for w in (
                select
                    "ExternalID"                                          as ext_id,
                    "CostObjectID"                                        as cost_code,
                    "CostObjectName"                                      as cost_name,
                    to_char(updatedate_actual, 'YYYY-MM-DD"T"HH24:MI:SS') as upd,
                    payload_json
                from
                    view_sequence_create
                where
                        project_id = proy.project_id
                    and tipo_objeto = 'WBS'
            ) loop
                l_object_ids.extend;
                l_object_ids(l_object_ids.count) := to_number ( w.ext_id );
                l_object_codes.extend;
                l_object_codes(l_object_codes.count) := w.cost_code;
                l_object_names.extend;
                l_object_names(l_object_names.count) := w.cost_name;
                l_update_dates.extend;
                l_update_dates(l_update_dates.count) := w.upd;
                if l_payload_lote is null then
                    l_payload_lote := '[' || w.payload_json;
                else
                    l_payload_lote := l_payload_lote
                                      || ','
                                      || w.payload_json;
                end if;

            end loop;

            if l_object_ids.count > 0 then
                l_payload_lote := l_payload_lote || ']';
                l_lotes_enviados := l_lotes_enviados + 1;
                enviar_lote(
                    p_project_id      => proy.project_id,
                    p_contract_number => proy.contract_number,
                    p_tipo_objeto     => 'WBS',
                    p_object_ids      => l_object_ids,
                    p_object_codes    => l_object_codes,
                    p_object_names    => l_object_names,
                    p_update_dates    => l_update_dates,
                    p_payload_lote    => l_payload_lote,
                    po_ok             => l_ok,
                    po_fallo          => l_fallo
                );

                l_tot_ok := l_tot_ok + l_ok;
                l_tot_fallo := l_tot_fallo + l_fallo;
                dbms_output.put_line('Proyecto '
                                     || proy.project_id
                                     || ' | WBS      | OK: '
                                     || l_ok
                                     || ' | FALLO: ' || l_fallo);

            end if;

            -- ============= LOTE 2: ACTIVIDADES =============
            l_object_ids := sys.odcinumberlist();
            l_object_codes := sys.odcivarchar2list();
            l_object_names := sys.odcivarchar2list();
            l_update_dates := sys.odcivarchar2list();
            l_payload_lote := null;
            for a in (
                select
                    "ExternalID"                                          as ext_id,
                    "CostObjectID"                                        as cost_code,
                    "CostObjectName"                                      as cost_name,
                    to_char(updatedate_actual, 'YYYY-MM-DD"T"HH24:MI:SS') as upd,
                    payload_json
                from
                    view_sequence_create
                where
                        project_id = proy.project_id
                    and tipo_objeto = 'ACTIVITY'
            ) loop
                l_object_ids.extend;
                l_object_ids(l_object_ids.count) := to_number ( a.ext_id );
                l_object_codes.extend;
                l_object_codes(l_object_codes.count) := a.cost_code;
                l_object_names.extend;
                l_object_names(l_object_names.count) := a.cost_name;
                l_update_dates.extend;
                l_update_dates(l_update_dates.count) := a.upd;
                if l_payload_lote is null then
                    l_payload_lote := '[' || a.payload_json;
                else
                    l_payload_lote := l_payload_lote
                                      || ','
                                      || a.payload_json;
                end if;

            end loop;

            if l_object_ids.count > 0 then
                l_payload_lote := l_payload_lote || ']';
                l_lotes_enviados := l_lotes_enviados + 1;
                enviar_lote(
                    p_project_id      => proy.project_id,
                    p_contract_number => proy.contract_number,
                    p_tipo_objeto     => 'ACTIVITY',
                    p_object_ids      => l_object_ids,
                    p_object_codes    => l_object_codes,
                    p_object_names    => l_object_names,
                    p_update_dates    => l_update_dates,
                    p_payload_lote    => l_payload_lote,
                    po_ok             => l_ok,
                    po_fallo          => l_fallo
                );

                l_tot_ok := l_tot_ok + l_ok;
                l_tot_fallo := l_tot_fallo + l_fallo;
                dbms_output.put_line('Proyecto '
                                     || proy.project_id
                                     || ' | ACTIVITY | OK: '
                                     || l_ok
                                     || ' | FALLO: ' || l_fallo);

            end if;

        end loop;

        dbms_output.put_line('=====================================================');
        dbms_output.put_line('TOTAL Lotes: '
                             || l_lotes_enviados
                             || ' | TOTAL OK: '
                             || l_tot_ok
                             || ' | TOTAL FALLO: ' || l_tot_fallo);

    end enviar_creacion;

    -- ============= ORQUESTACION DIARIA =============
    -- Ejecuta en orden: proyectos -> WBS -> actividades -> envio a Sequence.
    -- Si un paso falla, se propaga la excepcion y el scheduler marca el job
    -- como FAILED. Los pasos siguientes NO se ejecutan.
    procedure integracion_diaria is
        l_inicio timestamp := systimestamp;
        l_paso   varchar2(50);
    begin
        dbms_output.put_line('=== Inicio integracion diaria: '
                             || to_char(l_inicio, 'YYYY-MM-DD HH24:MI:SS') || ' ===');
        l_paso := 'cargar_proyectos';
        dbms_output.put_line('>>> Ejecutando ' || l_paso);
        pkg_carga_opc.cargar_proyectos;
        l_paso := 'cargar_wbs';
        dbms_output.put_line('>>> Ejecutando ' || l_paso);
        pkg_carga_opc.cargar_wbs;
        l_paso := 'cargar_actividades';
        dbms_output.put_line('>>> Ejecutando ' || l_paso);
        pkg_carga_opc.cargar_actividades;
        l_paso := 'enviar_creacion';
        dbms_output.put_line('>>> Ejecutando ' || l_paso);
        enviar_creacion;
        dbms_output.put_line('=== Fin integracion diaria: '
                             || to_char(systimestamp, 'YYYY-MM-DD HH24:MI:SS') || ' ===');
    exception
        when others then
            dbms_output.put_line('!!! FALLO en paso: ' || l_paso);
            dbms_output.put_line('!!! Error: ' || sqlerrm);
            raise;
    end integracion_diaria;

end pkg_envio_sequence;
/


-- sqlcl_snapshot {"hash":"0bcfaf903cc243929c9bba34d8cf043564c2bd65","type":"PACKAGE_BODY","name":"PKG_ENVIO_SEQUENCE","schemaName":"VERANOLINK","sxml":""}