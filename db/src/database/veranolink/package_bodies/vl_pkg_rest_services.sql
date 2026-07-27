create or replace package body veranolink.vl_pkg_rest_services as

    function vl_fn_rest_gettoken (
        iv_alias       varchar2,
        iv_company     varchar2,
        iv_environment number
    ) return clob as

        pragma autonomous_transaction;
        cursor c_geturl (
            vci_alias       varchar2,
            vci_company     varchar2,
            vci_environment number
        ) is
        select
            c.source_url || e.path_context source_url,
            c.source_authentication,
            a.id_vl_source_application,
            a.alias,
            f.call_name,
            e.id_vl_path_context
        from
            (
                (
                    (
                        (
                            (
                                     vl_source_applications a
                                inner join vl_companies_source_applications b on a.id_vl_source_application = b.id_vl_source_application
                            )
                            inner join vl_sources                       c on b.id_vl_company_application = c.id_vl_company_application
                        )
                        inner join vl_companies                     g on g.vl_id_company = b.vl_id_company
                    )
                    inner join vl_source_collections            d on d.id_vl_source_application = a.id_vl_source_application
                )
                inner join vl_path_contexts                 e on d.id_vl_source_collection = e.id_vl_source_collection
            )
            inner join vl_call_types                    f on f.id_vl_call_type = e.id_vl_call_type
        where
                a.alias = vci_alias
            and g.short_name = vci_company
            and c.id_vl_type_environment = vci_environment
            and c.source_authentication is not null
            and e.name = 'Get Token';

        cursor c_gettoken (
            vci_id_vl_source number
        ) is
        select
            1
        from
            vl_tokens
        where
            id_vl_source_application = vci_id_vl_source;

        l_geturl            c_geturl%rowtype;
        l_gettoken          c_gettoken%rowtype;
        l_exists_c_geturl   boolean;
        l_exists_c_gettoken boolean;
        l_http_request      utl_http.req;
        l_http_response     utl_http.resp;
        l_buffer_size       number := 4000;
        l_line_size         number := 16000;
        l_lines_count       number := 16000;
        l_string_request    varchar2(4000);
        l_line              clob;
        l_raw_data          raw(32767);
        l_resp_buffer       clob;
        l_content           varchar2(4000) := '';
        e_err_num           number;
        e_err_msg           varchar2(255);
        l_audit_log         number := dbms_utility.get_time;
    begin
        open c_geturl(iv_alias, iv_company, iv_environment);
        fetch c_geturl into l_geturl;
        l_exists_c_geturl := c_geturl%found;
        close c_geturl;
        if l_exists_c_geturl then
            apex_web_service.g_request_headers.delete();
            apex_web_service.g_request_headers(1).name := 'Authorization';
            apex_web_service.g_request_headers(1).value := 'Basic ' || l_geturl.source_authentication;
            l_resp_buffer := apex_web_service.make_rest_request(
                p_url         => utl_url.escape(l_geturl.source_url, false, 'UTF-8'),
                p_http_method => l_geturl.call_name
            );

            if apex_web_service.g_status_code != 500 then
                case l_geturl.alias
                    when 'OPU' then
                        declare
                            l_top_obje   json_object_t;
                            l_status     vl_tokens.status%type;
                            l_token      vl_tokens.access_token%type;
                            l_timezone   vl_tokens.timezone%type;
                            l_expirydate vl_tokens.expirydate%type;
                        begin
                            if l_resp_buffer != 'Unauthorized' then
                                l_top_obje := json_object_t(l_resp_buffer);
                                l_status := l_top_obje.get_string('status');
                                l_token := l_top_obje.get_string('token');
                                l_timezone := l_top_obje.get_string('Timezone');
                                l_expirydate := to_timestamp ( l_top_obje.get_string('expiryDate'),
                                'DD-MM-YYYY' );
                                open c_gettoken(l_geturl.id_vl_source_application);
                                fetch c_gettoken into l_gettoken;
                                l_exists_c_gettoken := c_gettoken%found;
                                close c_gettoken;
                                if l_exists_c_gettoken = false then
                                    insert into vl_tokens (
                                        status,
                                        expirydate,
                                        access_token,
                                        timezone,
                                        id_vl_source_application
                                    ) values
                                        ( l_status,
                                          l_expirydate,
                                          l_token,
                                          l_timezone,
                                          l_geturl.id_vl_source_application );

                                    commit;
                                else
                                    update vl_tokens
                                    set
                                        access_token = l_token,
                                        expirydate = l_expirydate,
                                        status = l_status,
                                        timezone = l_timezone
                                    where
                                        id_vl_source_application = l_geturl.id_vl_source_application;

                                    commit;
                                end if;

                            else
                                return '401';
                            end if;

                        end;
                    when 'OPC' then
                        declare
                            l_tokenopc         vl_tokens.access_token%type;
                            l_tokentype        vl_tokens.token_type%type;
                            l_primetenant      vl_tokens.primetenant%type;
                            l_primetenantcode  vl_tokens.primetenantcode%type;
                            l_userid           vl_tokens.userid%type;
                            l_primeidentityapp vl_tokens.primeidentityapp%type;
                            l_expirein         vl_tokens.expirein%type;
                            l_x_primetenant    vl_tokens.x_prime_tenant%type;
                            l_x_primeidentity  vl_tokens.x_prime_identity_app%type;
                            l_x_region         vl_tokens.x_prime_region%type;
                            l_top_obj          json_object_t;
                        begin
                            l_top_obj := json_object_t(l_resp_buffer);
                            l_tokenopc := l_top_obj.get_string('accessToken');
                            l_tokentype := l_top_obj.get_string('token_type');
                            l_primetenant := l_top_obj.get_string('primeTenant');
                            l_primetenantcode := l_top_obj.get_string('primeTenantCode');
                            l_userid := l_top_obj.get_string('userId');
                            l_primeidentityapp := l_top_obj.get_string('primeIdentityApp');
                            l_expirein := l_top_obj.get_string('expiresIn');
                            l_x_primetenant := l_top_obj.get_object('requestHeaders').get_string('x-prime-tenant');
                            l_x_primeidentity := l_top_obj.get_object('requestHeaders').get_string('x-prime-identity-app');
                            l_x_region := l_top_obj.get_object('requestHeaders').get_string('x-prime-region');
                            open c_gettoken(l_geturl.id_vl_source_application);
                            fetch c_gettoken into l_gettoken;
                            l_exists_c_gettoken := c_gettoken%found;
                            close c_gettoken;
                            if l_exists_c_gettoken = false then
                                insert into vl_tokens (
                                    access_token,
                                    token_type,
                                    primetenant,
                                    primetenantcode,
                                    userid,
                                    primeidentityapp,
                                    expirein,
                                    x_prime_tenant,
                                    x_prime_identity_app,
                                    x_prime_region,
                                    id_vl_source_application
                                ) values
                                    ( l_tokenopc,
                                      l_tokentype,
                                      l_primetenant,
                                      l_primetenantcode,
                                      l_userid,
                                      l_primeidentityapp,
                                      l_expirein,
                                      l_x_primetenant,
                                      l_x_primeidentity,
                                      l_x_region,
                                      l_geturl.id_vl_source_application );

                                commit;
                            else
                                update vl_tokens
                                set
                                    access_token = l_tokenopc,
                                    token_type = l_tokentype,
                                    primetenant = l_primetenant,
                                    primetenantcode = l_primetenantcode,
                                    userid = l_userid,
                                    primeidentityapp = l_primeidentityapp,
                                    expirein = l_expirein,
                                    x_prime_tenant = l_x_primetenant,
                                    x_prime_identity_app = l_x_primeidentity,
                                    x_prime_region = l_x_region
                                where
                                    id_vl_source_application = l_geturl.id_vl_source_application;

                                commit;
                            end if;

                        end;
                end case;
            else
                return to_clob('500');
            end if;

            vl_pkg_rest_services.vl_audit_logs(l_geturl.id_vl_path_context, iv_company, iv_alias, 'T-' || l_audit_log, apex_web_service.g_status_code
            ,
                                               'Inicio de sesi®n de ' || iv_company, null, systimestamp - interval '5' hour, l_geturl.call_name
                                               , 'Inicio de sesi®n de ' || iv_company);

        end if;

        return l_resp_buffer;
    exception
        when others then
          --      VL_PKG_REST_SERVICES.VL_AUDIT_LOGS(l_getURL.ID_VL_PATH_CONTEXT, IV_COMPANY, IV_ALIAS, 'T-' || l_AUDIT_LOG, APEX_WEB_SERVICE.g_status_code, 'Error inesperado : Mensaje' || SQLCODE || SQLERRM || ' Programa: ' || $$plsql_unit || ' L?nea ' || $$plsql_line || ' Backtrace: ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, NULL, l_getURL.CALL_NAME,NULL);
            return to_clob('Error inesperado : Mensaje'
                           || sqlcode
                           || sqlerrm
                           || ' Programa: '
                           || $$plsql_unit
                           || ' L?nea '
                           || $$plsql_line
                           || ' Backtrace: ' || dbms_utility.format_error_backtrace);
    end vl_fn_rest_gettoken;

    function vl_fn_rest_services (
        iv_filterurl     in varchar2 default null,
        iv_bodyrequest   in clob default null,
        iv_body_blob     in blob default null,
        iv_projectid     in varchar2 default null,
        iv_alias         varchar2,
        iv_company       varchar2,
        iv_methodcontext number,
        iv_environment   number
    ) return clob as

        pragma autonomous_transaction;
        cursor c_geturl (
            vci_pathcontext number,
            vci_alias       varchar2,
            vci_company     varchar2,
            vci_environment number
        ) is
        select
            c.source_url
            || ''
            || e.path_context full_url,
            f.call_name,
            a.alias,
            h.access_token,
            h.x_prime_identity_app,
            h.x_prime_region,
            h.x_prime_tenant,
            e.name            as name_api
        from
            (
                (
                    (
                        (
                            (
                                (
                                         vl_source_applications a
                                    inner join vl_companies_source_applications b on a.id_vl_source_application = b.id_vl_source_application
                                )
                                inner join vl_sources                       c on b.id_vl_company_application = c.id_vl_company_application
                            )
                            inner join vl_companies                     g on g.vl_id_company = b.vl_id_company
                        )
                        inner join vl_source_collections            d on d.id_vl_source_application = a.id_vl_source_application
                    )
                    inner join vl_path_contexts                 e on d.id_vl_source_collection = e.id_vl_source_collection
                )
                inner join vl_call_types                    f on f.id_vl_call_type = e.id_vl_call_type
            )
            inner join vl_tokens                        h on a.id_vl_source_application = h.id_vl_source_application
        where
                a.alias = vci_alias
            and g.short_name = vci_company
            and c.id_vl_type_environment = vci_environment
            and e.id_vl_path_context = vci_pathcontext;

        l_geturl          c_geturl%rowtype;
        l_exists_c_geturl boolean;
        l_soap_req_msg    varchar2(32767);
        l_soap_resp_msg   varchar2(32767);
        l_http_request    utl_http.req;
        l_http_response   utl_http.resp;
        l_content         clob;
        l_req_length      number;
        l_buffer          varchar2(32767);
        l_offset          number := 1;
        l_chunk_size      number := 20000; -- Tamao del segmento a leer del BLOB
        l_raw             raw(32767);
        l_base64_clob     clob;
        l_amount          number := 32767;
        l_line_size       number := 16000;
        l_lines_count     number := 16000;
        l_resp            clob;
        l_resp_blob       blob;
        l_line            clob;
        l_clob_response_1 clob;
        l_clob_response_2 clob;
        v_rest_token      clob;
        e_err_num         number;
        e_err_msg         varchar2(255);
        l_lengt           number;
        l_token_retry     clob;
        l_audit_log       number := dbms_utility.get_time;
        v_blob_body       blob;
        v_main_name_api   varchar2(4000);
    begin
        open c_geturl(iv_methodcontext, iv_alias, iv_company, iv_environment);
        fetch c_geturl into l_geturl;
        l_exists_c_geturl := c_geturl%found;
        close c_geturl;
        if l_exists_c_geturl then
            apex_web_service.g_request_headers.delete();
            apex_web_service.g_request_headers(1).name := 'Authorization';
            apex_web_service.g_request_headers(1).value := 'Bearer ' || l_geturl.access_token;
            apex_web_service.g_request_headers(2).name := 'x-prime-identity-app';
            apex_web_service.g_request_headers(2).value := l_geturl.x_prime_identity_app;
            apex_web_service.g_request_headers(3).name := 'x-prime-tenant';
            apex_web_service.g_request_headers(3).value := l_geturl.x_prime_tenant;
            apex_web_service.g_request_headers(4).name := 'x-prime-region';
            apex_web_service.g_request_headers(4).value := l_geturl.x_prime_region;
            apex_web_service.g_request_headers(5).name := 'Content-Type';
            apex_web_service.g_request_headers(5).value := 'application/json';
            if iv_bodyrequest is null then
                apex_web_service.g_request_headers(6).name := 'Content-Length';
                apex_web_service.g_request_headers(6).value := 0;
            end if;

            l_resp := apex_web_service.make_rest_request(
                p_url         => utl_url.escape(l_geturl.full_url
                                        || '/'
                                        || iv_filterurl, false, 'UTF-8'),
                p_http_method => l_geturl.call_name,
                p_body        => iv_bodyrequest
            );

            if apex_web_service.g_status_code = 401 then
                l_token_retry := vl_pkg_rest_services.vl_fn_rest_gettoken(iv_alias, iv_company, iv_environment);
                open c_geturl(iv_methodcontext, iv_alias, iv_company, iv_environment);
                fetch c_geturl into l_geturl;
                l_exists_c_geturl := c_geturl%found;
                close c_geturl;
                apex_web_service.g_request_headers.delete();
                apex_web_service.g_request_headers(1).name := 'Authorization';
                apex_web_service.g_request_headers(1).value := 'Bearer ' || l_geturl.access_token;
                apex_web_service.g_request_headers(2).name := 'x-prime-identity-app';
                apex_web_service.g_request_headers(2).value := l_geturl.x_prime_identity_app;
                apex_web_service.g_request_headers(3).name := 'x-prime-tenant';
                apex_web_service.g_request_headers(3).value := l_geturl.x_prime_tenant;
                apex_web_service.g_request_headers(4).name := 'x-prime-region';
                apex_web_service.g_request_headers(4).value := l_geturl.x_prime_region;
                apex_web_service.g_request_headers(5).name := 'Content-Type';
                apex_web_service.g_request_headers(5).value := 'application/json';
                if iv_bodyrequest is null then
                    apex_web_service.g_request_headers(6).name := 'Content-Length';
                    apex_web_service.g_request_headers(6).value := 0;
                end if;

                l_resp := apex_web_service.make_rest_request(
                    p_url         => utl_url.escape(l_geturl.full_url
                                            || '/'
                                            || iv_filterurl, false, 'UTF-8'),
                    p_http_method => l_geturl.call_name,
                    p_body        => iv_bodyrequest
                );

                if apex_web_service.g_status_code = 404 then
                    return to_clob('404');
                elsif apex_web_service.g_status_code = 204 then
                    return to_clob('204');
                elsif apex_web_service.g_status_code = 500 then
                    return to_clob('500');
                elsif apex_web_service.g_status_code = 401 then
                    return to_clob('401');
                end if;

            elsif apex_web_service.g_status_code = 404 then
                return to_clob('404');
            elsif apex_web_service.g_status_code = 204 then
                return to_clob('204');
            elsif apex_web_service.g_status_code = 500 then
                return to_clob('500');
            end if;

        end if;

        return l_resp;
    end vl_fn_rest_services;

    function vl_extract_api_response (
        iv_param_json   clob,
        iv_cod_context  number,
        iv_company_name varchar2,
        iv_environment  number
    ) return clob as

        pragma autonomous_transaction;
        l_application_name varchar2(50);
        l_top_obje         json_object_t;
        l_response         clob;
        l_method           varchar2(20);
        l_api_name         varchar2(1000);
        l_audit_log        number := dbms_utility.get_time;
        v_main_name_api    varchar2(4000);
    begin
        select
            a.alias
        into l_application_name
        from
                 vl_source_applications a
            inner join vl_source_collections b on a.id_vl_source_application = b.id_vl_source_application
            inner join vl_path_contexts      c on b.id_vl_source_collection = c.id_vl_source_collection
        where
            c.id_vl_path_context = iv_cod_context;

        select
            call_name
        into l_method
        from
                 vl_path_contexts a
            inner join vl_call_types b on a.id_vl_call_type = b.id_vl_call_type
        where
            a.id_vl_path_context = iv_cod_context;

        select
            a.name
        into l_api_name
        from
            vl_path_contexts a
        where
            a.id_vl_path_context = iv_cod_context;

        if iv_param_json is not null then
            l_top_obje := json_object_t(iv_param_json);
        end if;

      --    VL_PKG_REST_SERVICES.VL_AUDIT_LOGS(IV_COD_CONTEXT, IV_COMPANY_NAME, l_application_name, 'T-' || l_AUDIT_LOG, 0, 'Uso de la API: ' || l_api_name || ' , SOLICITADO POR: ' || IV_COMPANY_NAME, l_parameter.TO_CLOB(), l_method,l_api_name);

        case iv_cod_context
            when 261 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_number     varchar2(100);
                    l_bpname             varchar2(1000);
                    l_lineitem_fields    varchar2(10);
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(250);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_number := l_top_obje.get_string('project_number');
                    l_bpname := l_top_obje.get_string('bpname');
                    l_lineitem_fields := l_top_obje.get_string('lineitem_fields');
                    l_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_number,
                        iv_bodyrequest   => '{
                                            "bpname" : "'
                                          || l_bpname
                                          || '",
                                            "lineitem_fields":"'
                                          || l_lineitem_fields
                                          || '"
                                            }',
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => 261,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_number,
                            iv_bodyrequest   => '{
                                            "bpname" : "'
                                              || l_bpname
                                              || '",
                                            "lineitem_fields":"'
                                              || l_lineitem_fields
                                              || '"
                                            }',
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => 261,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 603 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de BP no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 105 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_parent_path        varchar2(1000);
                    l_projectnumber      varchar2(1000);
                    l_lineitem_fields    varchar2(10);
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(250);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_parent_path := l_top_obje.get_string('parentpath');
                    l_projectnumber := l_top_obje.get_string('projectnumber');
                    l_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?projectnumber='
                                        || l_projectnumber
                                        || '&parentpath='
                                        || l_parent_path,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => 105,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?projectnumber='
                                            || l_projectnumber
                                            || '&parentpath='
                                            || l_parent_path,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => 105,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 603 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de BP no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1039 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Parent Path invalido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 106 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    parent_folder_id     varchar2(1000);
                    nodetype             varchar2(1000);
                    l_nodetype_validator varchar2(1100);
                    l_lineitem_fields    varchar2(10);
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(250);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    parent_folder_id := l_top_obje.get_string('parent_folder_id');
                    nodetype := l_top_obje.get_string('nodetype');
                    if nodetype is null
                       or nodetype = 'null'
                    or nodetype = 'NULL'
                    or nodetype = '' then
                        l_nodetype_validator := '';
                    else
                        l_nodetype_validator := '?nodetype=' || nodetype;
                    end if;

                    l_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => parent_folder_id || l_nodetype_validator,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => 106,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => parent_folder_id || l_nodetype_validator,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => 106,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 1039 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Folder ID no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1049 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Nodetype no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 112 then
                declare
                    l_parameter               json_object_t := json_object_t();
                    l_param_obj               json_object_t;
                    projectnumber             varchar2(1000);
                    node_path                 varchar2(1000);
                    l_projectnumber_validator varchar2(1100);
                    l_lineitem_fields         varchar2(10);
                    l_response_validator      json_object_t;
                    l_response_r              varchar2(250);
                    l_end_response            varchar2(250);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    projectnumber := l_top_obje.get_string('projectnumber');
                    node_path := l_top_obje.get_string('node_path');
                    if projectnumber is null
                       or projectnumber = 'null'
                    or projectnumber = 'NULL'
                    or projectnumber = '' then
                        l_projectnumber_validator := '';
                    else
                        l_projectnumber_validator := projectnumber || '/';
                    end if;

                    l_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => projectnumber
                                        || 'node/'
                                        || node_path,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => 112,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectnumber_validator
                                            || 'node/'
                                            || node_path,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => 112,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 1074 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'El nodepath no existe',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 114 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_num        varchar2(2000);
                    l_record_no          varchar2(1000);
                    l_bpname             varchar2(1100);
                    l_lineitem_fields    varchar2(10);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(250);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_num := l_top_obje.get_string('project_num');
                    l_record_no := l_top_obje.get_string('record_no');
                    l_bpname := l_top_obje.get_string('bpname');
                    l_lineitem_fields := l_top_obje.get_string('lineitem');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_num
                                        || '?input={"bpname" : "'
                                        || l_bpname
                                        || '","record_no" : "'
                                        || l_record_no
                                        || '","lineitem":"'
                                        || l_lineitem_fields
                                        || '"}',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_num
                                            || '?input={"bpname" : "'
                                            || l_bpname
                                            || '","record_no" : "'
                                            || l_record_no
                                            || '","lineitem":"'
                                            || l_lineitem_fields
                                            || '"}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => 114,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 603 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de BP no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 657 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'recod_no invalido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 115 then
                declare
                    l_parameter               json_object_t := json_object_t();
                    l_param_obj               json_object_t;
                    l_project_num             varchar2(2000);
                    l_record_no               varchar2(1000);
                    l_bpname                  varchar2(1100);
                    l_lineitem_fields         varchar2(10);
                    l_lineitem_file           varchar2(10);
                    l_general_comments        varchar2(10);
                    l_attach_all_publications varchar2(10);
                    l_api_response            clob;
                    l_response_validator      json_object_t;
                    l_response_r              varchar2(250);
                    l_end_response            varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_num := l_top_obje.get_string('project_num');
                    l_record_no := l_top_obje.get_string('record_no');
                    l_bpname := l_top_obje.get_string('bpname');
                    l_lineitem_fields := l_top_obje.get_string('lineitem');
                    l_lineitem_file := l_top_obje.get_string('lineitem_file');
                    l_general_comments := l_top_obje.get_string('general_comments');
                    l_attach_all_publications := l_top_obje.get_string('attach_all_publications');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_num
                                        || '?input={"bpname":"'
                                        || l_bpname
                                        || '","record_no":"'
                                        || l_record_no
                                        || '","lineitem":"'
                                        || l_lineitem_fields
                                        || '","lineitem_file":"'
                                        || l_lineitem_file
                                        || '","general_comments":"'
                                        || l_general_comments
                                        || '","attach_all_publications":"'
                                        || l_general_comments
                                        || '"}',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_num
                                            || '?input={"bpname":"'
                                            || l_bpname
                                            || '","record_no":"'
                                            || l_record_no
                                            || '","lineitem":"'
                                            || l_lineitem_fields
                                            || '","lineitem_file":"'
                                            || l_lineitem_file
                                            || '","general_comments":"'
                                            || l_general_comments
                                            || '","attach_all_publications":"'
                                            || l_general_comments
                                            || '"}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 603 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de BP no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 657 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'recod_no invalido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 125 then
                declare
                    l_project_num        varchar2(2000);
                    l_record_no          varchar2(1000);
                    l_bpname             varchar2(1100);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_num := l_top_obje.get_string('project_number');
                    l_record_no := l_top_obje.get_string('record_no');
                    l_bpname := l_top_obje.get_string('bpname');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_num
                                        || '?input= {"bpname" : "'
                                        || l_bpname
                                        || '","record_no" : "'
                                        || l_record_no
                                        || '"}',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_num
                                            || '?input= {"bpname" : "'
                                            || l_bpname
                                            || '","record_no" : "'
                                            || l_record_no
                                            || '"}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 603 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de BP no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 657 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'recod_no invalido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 133 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_num        varchar2(2000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_num := l_top_obje.get_string('project_number');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?project_number=' || l_project_num,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?project_number=' || l_project_num,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 138 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_num        varchar2(2000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_num := l_top_obje.get_string('project_number');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?project_number=' || l_project_num,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?project_number=' || l_project_num,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 107 then
                declare
                    l_shell_type         varchar2(2000);
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_shell_type := l_top_obje.get_string('shell_type');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?options={"filter": {"shell_type" : "'
                                        || l_shell_type
                                        || '"}}',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?options={"filter": {"shell_type" : "'
                                            || l_shell_type
                                            || '"}}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 2051 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Shell Type invalido o no esta activo',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 134 then
                declare
                    l_status             varchar2(100);
                    l_type               varchar2(100);
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_status := l_top_obje.get_string('status');
                    l_type := l_top_obje.get_string('type');
                    if l_status is null then
                        l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                            iv_filterurl     => '',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        l_response_validator := json_object_t(l_api_response);
                        l_response_r := l_response_validator.get_number('status');
                        if l_response_r = 200 then
                            l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                                iv_filterurl     => '',
                                iv_bodyrequest   => null,
                                iv_projectid     => null,
                                iv_alias         => l_application_name,
                                iv_company       => iv_company_name,
                                iv_methodcontext => iv_cod_context,
                                iv_environment   => iv_environment
                            );

                            return l_end_response;
                        end if;

                    elsif
                        l_status is not null
                        and l_type is null
                    then
                        l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                            iv_filterurl     => '?options={ "status": "'
                                            || l_status
                                            || '"}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        l_response_validator := json_object_t(l_api_response);
                        l_response_r := l_response_validator.get_number('status');
                        if l_response_r = 200 then
                            l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                                iv_filterurl     => '?options={ "status": "'
                                                || l_status
                                                || '"}',
                                iv_bodyrequest   => null,
                                iv_projectid     => null,
                                iv_alias         => l_application_name,
                                iv_company       => iv_company_name,
                                iv_methodcontext => iv_cod_context,
                                iv_environment   => iv_environment
                            );

                            vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                               iv_company_name,
                                                               l_application_name,
                                                               'T-' || l_audit_log,
                                                               l_response_r,
                                                               'Uso de la API: '
                                                               || l_api_name
                                                               || ' , SOLICITADO POR: '
                                                               || iv_company_name,
                                                               l_parameter.to_clob(),
                                                               systimestamp - interval '5' hour,
                                                               l_method,
                                                               l_api_name);

                            return l_end_response;
                        end if;

                    elsif
                        l_status is null
                        and l_type is not null
                    then
                        l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                            iv_filterurl     => '?options={ "type": "'
                                            || l_type
                                            || '"}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        l_response_validator := json_object_t(l_api_response);
                        l_response_r := l_response_validator.get_number('status');
                        if l_response_r = 200 then
                            l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                                iv_filterurl     => '?options={ "type": "'
                                                || l_type
                                                || '"}',
                                iv_bodyrequest   => null,
                                iv_projectid     => null,
                                iv_alias         => l_application_name,
                                iv_company       => iv_company_name,
                                iv_methodcontext => iv_cod_context,
                                iv_environment   => iv_environment
                            );

                            select
                                name
                            into v_main_name_api
                            from
                                vl_path_contexts
                            where
                                id_vl_path_context = 134;

                            vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                               iv_company_name,
                                                               l_application_name,
                                                               'T-' || l_audit_log,
                                                               l_response_r,
                                                               'Uso de la API: '
                                                               || l_api_name
                                                               || ' , SOLICITADO POR: '
                                                               || iv_company_name,
                                                               l_parameter.to_clob(),
                                                               systimestamp - interval '5' hour,
                                                               l_method,
                                                               l_api_name);

                            return l_end_response;
                        end if;

                    elsif
                        l_status is not null
                        and l_type is not null
                    then
                        l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                            iv_filterurl     => '?options={ "status": "'
                                            || l_status
                                            || '","type":"'
                                            || l_type
                                            || '"}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        l_response_validator := json_object_t(l_api_response);
                        l_response_r := l_response_validator.get_number('status');
                        if l_response_r = 200 then
                            l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                                iv_filterurl     => '?options={ "status": "'
                                                || l_status
                                                || '","type":"'
                                                || l_type
                                                || '"}',
                                iv_bodyrequest   => null,
                                iv_projectid     => null,
                                iv_alias         => l_application_name,
                                iv_company       => iv_company_name,
                                iv_methodcontext => iv_cod_context,
                                iv_environment   => iv_environment
                            );

                            vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                               iv_company_name,
                                                               l_application_name,
                                                               'T-' || l_audit_log,
                                                               l_response_r,
                                                               'Uso de la API: '
                                                               || l_api_name
                                                               || ' , SOLICITADO POR: '
                                                               || iv_company_name,
                                                               l_parameter.to_clob(),
                                                               systimestamp - interval '5' hour,
                                                               l_method,
                                                               l_api_name);

                            return l_end_response;
                        elsif l_response_r = 1059 then
                            vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                               iv_company_name,
                                                               l_application_name,
                                                               'T-' || l_audit_log,
                                                               l_response_r,
                                                               'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                               ,
                                                               l_parameter.to_clob(),
                                                               systimestamp - interval '5' hour,
                                                               l_method,
                                                               l_api_name);

                            return l_response_r;
                        end if;

                    end if;

                end;
            when 135 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_number     varchar2(2000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_number := l_top_obje.get_string('project_number');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?project_number=' || l_project_number,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?project_number=' || l_project_number,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 302 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_number     varchar2(2000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_number := l_top_obje.get_string('project_num');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_number,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_number,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 151 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_names              varchar2(2000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_names := l_top_obje.get_string('names');
                    if l_names is null then
                        l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                            iv_filterurl     => '',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );
                    else
                        l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                            iv_filterurl     => '?filter={"names":["'
                                            || l_names
                                            || '"]}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );
                    end if;

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        if l_names is null then
                            l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                                iv_filterurl     => '',
                                iv_bodyrequest   => null,
                                iv_projectid     => null,
                                iv_alias         => l_application_name,
                                iv_company       => iv_company_name,
                                iv_methodcontext => iv_cod_context,
                                iv_environment   => iv_environment
                            );
                        else
                            l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                                iv_filterurl     => '?filter={"names":["'
                                                || l_names
                                                || '"]}',
                                iv_bodyrequest   => null,
                                iv_projectid     => null,
                                iv_alias         => l_application_name,
                                iv_company       => iv_company_name,
                                iv_methodcontext => iv_cod_context,
                                iv_environment   => iv_environment
                            );
                        end if;

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 153 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_name               varchar2(2000);
                    l_project_number     varchar2(2000);
                    l_main_sheet         varchar2(20);
                    l_sheet_lock         varchar2(20);
                    l_status             varchar2(20);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_name := l_top_obje.get_string('name');
                    l_project_number := l_top_obje.get_string('project_number');
                    l_main_sheet := l_top_obje.get_string('main_sheet');
                    l_sheet_lock := l_top_obje.get_string('sheet_lock');
                    l_status := l_top_obje.get_string('status');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_number
                                        || '?filter={"name":"'
                                        || l_name
                                        || '","status": "'
                                        || l_status
                                        || '","main_sheet":"'
                                        || l_main_sheet
                                        || '","sheet_lock":"'
                                        || l_sheet_lock
                                        || '"}',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_number
                                            || '?filter={"name":"'
                                            || l_name
                                            || '","status": "'
                                            || l_status
                                            || '","main_sheet":"'
                                            || l_main_sheet
                                            || '","sheet_lock":"'
                                            || l_sheet_lock
                                            || '"}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 152 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_number     varchar2(2000);
                    l_sheetname          varchar2(2000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_number := l_top_obje.get_string('project_number');
                    l_sheetname := l_top_obje.get_string('sheetname');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_number
                                        || '?sheetname="'
                                        || l_sheetname
                                        || '"',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_number
                                            || '?sheetname="'
                                            || l_sheetname
                                            || '"',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 713 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'El nombre de la hoja de programaci?n no es v?lido.',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 154 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 157 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_dds_name           varchar2(2000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_dds_name := l_top_obje.get_string('dds_name');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?dds_name=' || l_dds_name,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?dds_name=' || l_dds_name,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 3000 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 155 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_data_element       varchar2(2000);
                    l_data_definition    varchar2(2000);
                    l_form_label         varchar2(2000);
                    l_description        varchar2(2000);
                    l_tooltip            varchar2(2000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_data_element := l_top_obje.get_string('data_element');
                    l_data_definition := l_top_obje.get_string('data_definition');
                    l_form_label := l_top_obje.get_string('form_label');
                    l_description := l_top_obje.get_string('description');
                    l_tooltip := l_top_obje.get_string('tooltip');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?filter={"data_element": "'
                                        || l_data_element
                                        || '","data_definition": "'
                                        || l_data_definition
                                        || '" ,"form_label": "'
                                        || l_form_label
                                        || '" ,"description": "'
                                        || l_description
                                        || '" ,"tooltip": "'
                                        || l_tooltip
                                        || '"}',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?filter={"data_element": "'
                                            || l_data_element
                                            || '","data_definition": "'
                                            || l_data_definition
                                            || '" ,"form_label": "'
                                            || l_form_label
                                            || '" ,"description": "'
                                            || l_description
                                            || '" ,"tooltip": "'
                                            || l_tooltip
                                            || '"}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 3000 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 158 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_type               varchar2(100);
                    l_name               varchar2(3000);
                    l_data_source        varchar2(3000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_type := l_top_obje.get_string('type');
                    l_name := l_top_obje.get_string('name');
                    l_data_source := l_top_obje.get_string('data_source');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?type='
                                        || l_type
                                        || '&filter={"name":"'
                                        || l_name
                                        || '", "data_source":"'
                                        || l_data_source
                                        || '"}',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?type='
                                            || l_type
                                            || '&filter={"name":"'
                                            || l_name
                                            || '", "data_source":"'
                                            || l_data_source
                                            || '"}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 3000 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 156 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_dds_name           varchar2(2000);
                    l_master_de_name     varchar2(3000);
                    l_dds_desc           varchar2(3000);
                    l_master_de_label    varchar2(3000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_dds_name := l_top_obje.get_string('dds_name');
                    l_master_de_name := l_top_obje.get_string('master_de_name');
                    l_dds_desc := l_top_obje.get_string('dds_desc');
                    l_master_de_label := l_top_obje.get_string('master_de_label');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?filter={"dds_name": "'
                                        || l_dds_name
                                        || '","master_de_name": "'
                                        || l_master_de_name
                                        || '","dds_desc": "'
                                        || l_dds_desc
                                        || '","master_de_label": "'
                                        || l_master_de_label
                                        || '"}',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?filter={"dds_name": "'
                                            || l_dds_name
                                            || '","master_de_name": "'
                                            || l_master_de_name
                                            || '","dds_desc": "'
                                            || l_dds_desc
                                            || '","master_de_label": "'
                                            || l_master_de_label
                                            || '"}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 3000 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 159 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_shortname          varchar2(2000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_shortname := l_top_obje.get_string('shortname');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?shortname=' || l_shortname,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?shortname=' || l_shortname,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 3000 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 505 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Dato no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 163 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_status             varchar2(50);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_status := l_top_obje.get_string('status');
                    if l_status = 'Active' then
                        l_status := '1';
                    else
                        l_status := '0';
                    end if;

                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => null,
                        iv_bodyrequest   => '{

"filterCondition":"uuu_user_status='
                                          || l_status
                                          || '"
}',
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => null,
                            iv_bodyrequest   => '{

"filterCondition":"uuu_user_status='
                                              || l_status
                                              || '"
}',
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 3000 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 505 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Dato no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 164 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectnumber      varchar2(2000);
                    l_reportname         varchar2(2000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectnumber := l_top_obje.get_string('projectnumber');
                    l_reportname := l_top_obje.get_string('reportname');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectnumber,
                        iv_bodyrequest   => '{

"reportname":"'
                                          || l_reportname
                                          || '"

}',
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectnumber,
                            iv_bodyrequest   => '{

"reportname":"'
                                              || l_reportname
                                              || '"

}',
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 709 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'El nombre del informe no es v?lido. Verifique si el informe existe o est? habilitado para la integraci?n.'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 165 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_number     varchar2(2000);
                    l_curve_name         varchar2(2000);
                    l_rollup_status      varchar2(100);
                    l_detail_level       varchar2(100);
                    l_include_curves     varchar2(100);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_number := l_top_obje.get_string('project_number');
                    l_curve_name := l_top_obje.get_string('curve_name');
                    l_rollup_status := l_top_obje.get_string('rollup_status');
                    l_detail_level := l_top_obje.get_string('detail_level');
                    l_include_curves := l_top_obje.get_string('include_curves');
                    if l_curve_name is not null then
                        l_curve_name := '"curve_name":"'
                                        || l_curve_name
                                        || '",';
                    end if;

                    if l_rollup_status is not null then
                        l_rollup_status := '"rollup_status":"'
                                           || l_rollup_status
                                           || '",';
                    else
                        l_rollup_status := '';
                    end if;

                    if l_detail_level is not null then
                        l_detail_level := '"detail_level":"'
                                          || l_detail_level
                                          || '",';
                    end if;

                    if l_include_curves is not null then
                        l_include_curves := '"include_curves":"'
                                            || l_include_curves
                                            || '",';
                    end if;

                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_number,
                        iv_bodyrequest   => '{
    "options": {

       '
                                          || l_curve_name
                                          || l_rollup_status
                                          || l_detail_level
                                          || l_include_curves
                                          || '
    }
}',
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_number,
                            iv_bodyrequest   => '{
    "options": {

       '
                                              || l_curve_name
                                              || l_rollup_status
                                              || l_detail_level
                                              || l_include_curves
                                              || '
    }
}',
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 709 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'El nombre del informe no es v?lido. Verifique si el informe existe o est? habilitado para la integraci?n.'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 166 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_shell_number       varchar2(1000);
                    l_object_name        varchar2(1000);
                    l_record_no          varchar2(1000);
                    l_new_status         varchar2(1000);
                    l_old_status         varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_shell_number := l_top_obje.get_string('shell_number');
                    l_object_name := l_top_obje.get_string('object_name');
                    l_record_no := l_top_obje.get_string('record_no');
                    l_new_status := l_top_obje.get_string('new_status');
                    l_old_status := l_top_obje.get_string('old_status');
                    if l_shell_number is not null then
                        l_shell_number := '"shell_number":"'
                                          || l_shell_number
                                          || '",';
                    end if;

                    if l_object_name is not null then
                        l_object_name := '"object_name":"'
                                         || l_object_name
                                         || '",';
                    end if;

                    if l_record_no is not null then
                        l_record_no := '"record_no":"'
                                       || l_record_no
                                       || '",';
                    end if;

                    if l_new_status is not null then
                        l_new_status := '"new_status":"'
                                        || l_new_status
                                        || '",';
                    end if;

                    if l_old_status is not null then
                        l_old_status := '"old_status":"'
                                        || l_old_status
                                        || '",';
                    end if;

                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?filter={'
                                        || l_shell_number
                                        || l_object_name
                                        || l_record_no
                                        || l_new_status
                                        || l_old_status
                                        || '}',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?filter={'
                                            || l_shell_number
                                            || l_object_name
                                            || l_record_no
                                            || l_new_status
                                            || l_old_status
                                            || '}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 709 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'El nombre del informe no es v?lido. Verifique si el informe existe o est? habilitado para la integraci?n.'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 167 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_number     varchar2(1000);
                    l_category           varchar2(1000);
                    l_status             varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_number := l_top_obje.get_string('project_number');
                    l_category := l_top_obje.get_string('category');
                    l_status := l_top_obje.get_string('status');
                    if l_category is not null then
                        l_category := '"category":"'
                                      || l_category
                                      || '",';
                    end if;

                    if l_status is not null then
                        l_status := '"status":"'
                                    || l_status
                                    || '",';
                    end if;

                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_number
                                        || '?filter={'
                                        || l_category
                                        || l_status
                                        || ' }',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_number
                                            || '?filter={'
                                            || l_category
                                            || l_status
                                            || ' }',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 709 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'El nombre del informe no es v?lido. Verifique si el informe existe o est? habilitado para la integraci?n.'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Codigo de proyecto no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 140 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_name               varchar2(3000);
                    l_project_number     varchar2(100);
                    l_curves             varchar2(3000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_name := l_top_obje.get_string('name');
                    l_project_number := l_top_obje.get_string('project_number');
                    l_curves := l_top_obje.get_string('curves');
                    if l_curves is not null then
                        l_curves := '"curves":["'
                                    || l_curves
                                    || '"],';
                    end if;

                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_number
                                        || '?filter={ "name":"'
                                        || l_name
                                        || '",'
                                        || l_curves
                                        || '}',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_number
                                            || '?filter={ "name":"'
                                            || l_name
                                            || '",'
                                            || l_curves
                                            || '}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 3000 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1305 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Cash Flow no existe',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 149 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_number     varchar2(100);
                    l_names              varchar2(3000);
                    l_curve_name         varchar2(3000);
                    l_rollup_status      varchar2(3000);
                    l_detail_level       varchar2(3000);
                    l_include_curves     varchar2(3000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_number := l_top_obje.get_string('project_number');
                    l_names := l_top_obje.get_string('names');
                    l_curve_name := l_top_obje.get_string('curve_name');
                    l_rollup_status := l_top_obje.get_string('rollup_status');
                    l_detail_level := l_top_obje.get_string('detail_level');
                    l_include_curves := l_top_obje.get_string('include_curves');
                    if l_project_number is not null then
                        l_project_number := l_project_number;
                    end if;
                    if l_names is not null then
                        l_names := '"names":"'
                                   || l_names
                                   || '",';
                    else
                        l_names := '';
                    end if;

                    if l_curve_name is not null then
                        l_curve_name := '"curve_name":"'
                                        || l_curve_name
                                        || '",';
                    else
                        l_curve_name := '';
                    end if;

                    if l_rollup_status is not null then
                        l_rollup_status := '"rollup_status":"'
                                           || l_rollup_status
                                           || '",';
                    else
                        l_rollup_status := '';
                    end if;

                    if l_detail_level is not null then
                        l_detail_level := '"detail_level":"'
                                          || l_detail_level
                                          || '",';
                    else
                        l_detail_level := '';
                    end if;

                    if l_include_curves is not null then
                        l_include_curves := '"include_curves":"'
                                            || l_include_curves
                                            || '",';
                    else
                        l_include_curves := '';
                    end if;

                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_number
                                        || '?filter={'
                                        || l_names
                                        || l_curve_name
                                        || l_rollup_status
                                        || l_detail_level
                                        || l_include_curves
                                        || '}',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_number
                                            || '?filter={'
                                            || l_names
                                            || l_curve_name
                                            || l_rollup_status
                                            || l_detail_level
                                            || l_include_curves
                                            || '}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 3000 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Project_number no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 150 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_number     varchar2(100);
                    l_names              varchar2(3000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_number := l_top_obje.get_string('project_number');
                    l_names := l_top_obje.get_string('names');
                    if l_project_number is not null then
                        l_project_number := l_project_number;
                    end if;
                    if l_names is not null then
                        l_names := '"names":"'
                                   || l_names
                                   || '",';
                    else
                        l_names := '';
                    end if;

                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_number
                                        || '?filter={'
                                        || l_names
                                        || '}',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_number
                                            || '?filter={'
                                            || l_names
                                            || '}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 3000 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Project_number no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 142 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_number     varchar2(100);
                    l_names              varchar2(3000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_number := l_top_obje.get_string('project_number');
                    l_names := l_top_obje.get_string('names');
                    if l_names is not null then
                        l_names := '"names":"'
                                   || l_names
                                   || '",';
                    else
                        l_names := '';
                    end if;

                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_number
                                        || '?filter={'
                                        || l_names
                                        || '}',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_number
                                            || '?filter={'
                                            || l_names
                                            || '}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 3000 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Project_number no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 169 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_number     varchar2(100);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_number := l_top_obje.get_string('project_number');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_number,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_number,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 3000 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Project_number no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 170 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_number     varchar2(1000);
                    l_cbs_codes          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_number := l_top_obje.get_string('project_number');
                    l_cbs_codes := l_top_obje.get_string('cbs_codes');
                    if l_cbs_codes is not null then
                        l_cbs_codes := '"cbs_codes":["'
                                       || l_cbs_codes
                                       || '"]';
                    end if;

                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_number
                                        || '?filter={'
                                        || l_cbs_codes
                                        || '}',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_number
                                            || '?filter={'
                                            || l_cbs_codes
                                            || '}',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 3000 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Project_number no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 707 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'No existe hoja de costo',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 179 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_number     varchar2(1000);
                    l_bpname             varchar2(1000);
                    l_record_no          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_project_number := l_top_obje.get_string('project_number');
                    l_bpname := l_top_obje.get_string('bpname');
                    l_record_no := l_top_obje.get_string('record_no');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_number,
                        iv_bodyrequest   => '{

"bpname" : "'
                                          || l_bpname
                                          || '"
,
"record_no" : "'
                                          || l_record_no
                                          || '"
}',
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    l_response_validator := json_object_t(l_api_response);
                    l_response_r := l_response_validator.get_number('status');
                    if l_response_r = 200 then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_number,
                            iv_bodyrequest   => '{

"bpname" : "'
                                              || l_bpname
                                              || '"
,
"record_no" : "'
                                              || l_record_no
                                              || '"
}',
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_response_r = 3000 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 811 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 500 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Internal error, revisar errores',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 1059 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Un parametro tiene caracteres especiales, no se puede hacer PARSE al JSON'
                                                           ,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 602 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Project_number no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 603 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Bpname no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    elsif l_response_r = 3002 then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           l_response_r,
                                                           'Item de entrada no es valido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_response_r;
                    end if;

                end;
            when 309 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_project_number     varchar2(1000);
                    l_bpname             varchar2(1000);
                    l_record_no          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_project_number,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_project_number,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           200,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro de WORKSPACEID no es v?lido', 'Parameters: ' || l_project_number
                                                           , systimestamp - interval '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_project_number, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_project_number, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                    return l_end_response;
                end;
            when 304 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        number;
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           200,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro de WORKSPACEID no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 305 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectid          number;
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectid := l_top_obje.get_number('projectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           200,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro de projectId no es v?lido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_projectid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 306 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectname        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectname := l_top_obje.get_string('projectName');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectname,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectname,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           200,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name,
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           404,
                                                           'Parametro de projectId no es v?lido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           204,
                                                           'No hay contenido',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context,
                                                           iv_company_name,
                                                           l_application_name,
                                                           'T-' || l_audit_log,
                                                           204,
                                                           'Error interno',
                                                           l_parameter.to_clob(),
                                                           systimestamp - interval '5' hour,
                                                           l_method,
                                                           l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 4 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_jobid              varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_jobid := l_top_obje.get_string('jobId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_jobid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_jobid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_jobid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_jobid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_jobid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_jobid, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 5 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectbaselineid  varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectbaselineid := l_top_obje.get_string('projectBaselineId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectbaselineid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectbaselineid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_projectbaselineid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_projectbaselineid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_projectbaselineid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_projectbaselineid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 6 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectcode        varchar2(1000);
                    l_worpacecode        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectcode := l_top_obje.get_string('projectCode');
                    l_worpacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?projectCode='
                                        || l_projectcode
                                        || '&workspaceCode='
                                        || l_worpacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?projectCode='
                                            || l_projectcode
                                            || '&workspaceCode='
                                            || l_worpacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_projectcode
                                                                               || ','
                                                                               || l_worpacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_projectcode
                                                                                     || ','
                                                                                     || l_worpacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_projectcode
                                                                               || ','
                                                                               || l_worpacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_projectcode
                                                                            || ','
                                                                            || l_worpacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 7 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_id,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_id,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_id, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_id, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_id, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_id, systimestamp - interval '5' hour,
                                                           l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 8 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_id,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_id,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_id, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_id, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_id, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_id, systimestamp - interval '5' hour,
                                                           l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 9 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_baselinename       varchar2(1000);
                    l_baselinetype       varchar2(1000);
                    l_projectcode        varchar2(1000);
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_baselinename := l_top_obje.get_string('baselineName');
                    l_baselinetype := l_top_obje.get_string('baselineType');
                    l_projectcode := l_top_obje.get_string('projectCode');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?projectCode='
                                        || l_projectcode
                                        || '&baselineType='
                                        || l_baselinetype
                                        || '&baselineName='
                                        || l_baselinename
                                        || '&workspaceCode='
                                        || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?projectCode='
                                            || l_projectcode
                                            || '&baselineType='
                                            || l_baselinetype
                                            || '&baselineName='
                                            || l_baselinename
                                            || '&workspaceCode='
                                            || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_baselinename
                                                                               || ','
                                                                               || l_baselinetype
                                                                               || ','
                                                                               || l_projectcode
                                                                               || ','
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_baselinename
                                                                                     || ','
                                                                                     || l_baselinetype
                                                                                     || ','
                                                                                     || l_projectcode
                                                                                     || ','
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_baselinename
                                                                               || ','
                                                                               || l_baselinetype
                                                                               || ','
                                                                               || l_projectcode
                                                                               || ','
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_baselinename
                                                                            || ','
                                                                            || l_baselinetype
                                                                            || ','
                                                                            || l_projectcode
                                                                            || ','
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 10 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_activycode         varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_activycode := l_top_obje.get_string('activityCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_activycode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_activycode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_activycode, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_activycode, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_activycode, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_activycode, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 11 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectid          varchar2(1000);
                    l_value              varchar2(1000);
                    l_viewcolumnname     varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectid := l_top_obje.get_string('projectId');
                    l_value := l_top_obje.get_string('value');
                    l_viewcolumnname := l_top_obje.get_string('viewColumnName');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectid
                                        || '/configuredField/'
                                        || l_viewcolumnname
                                        || '/'
                                        || l_value,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectid
                                            || '/configuredField/'
                                            || l_viewcolumnname
                                            || '/'
                                            || l_value,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_projectid
                                                                               || ','
                                                                               || l_viewcolumnname
                                                                               || ','
                                                                               || l_value, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_projectid
                                                                                     || ','
                                                                                     || l_viewcolumnname
                                                                                     || ','
                                                                                     || l_value, systimestamp - interval '5' hour, l_method
                                                                                     , l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_projectid
                                                                               || ','
                                                                               || l_viewcolumnname
                                                                               || ','
                                                                               || l_value, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_projectid
                                                                            || ','
                                                                            || l_viewcolumnname
                                                                            || ','
                                                                            || l_value, systimestamp - interval '5' hour, l_method, l_api_name
                                                                            );

                        return to_clob('500');
                    end if;

                end;
            when 12 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectid          varchar2(1000);
                    l_codetypeid         varchar2(1000);
                    l_codevaluecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectid := l_top_obje.get_string('projectId');
                    l_codetypeid := l_top_obje.get_string('codeTypeId');
                    l_codevaluecode := l_top_obje.get_string('codeValueCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectid
                                        || '/codeType/'
                                        || l_codetypeid
                                        || '/codeValue/'
                                        || l_codevaluecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectid
                                            || '/codeType/'
                                            || l_codetypeid
                                            || '/codeValue/'
                                            || l_codevaluecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_projectid
                                                                               || '/codeType/'
                                                                               || l_codetypeid
                                                                               || '/codeValue/'
                                                                               || l_codevaluecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_projectid
                                                                                     || '/codeType/'
                                                                                     || l_codetypeid
                                                                                     || '/codeValue/'
                                                                                     || l_codevaluecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_projectid
                                                                               || '/codeType/'
                                                                               || l_codetypeid
                                                                               || '/codeValue/'
                                                                               || l_codevaluecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_projectid
                                                                            || '/codeType/'
                                                                            || l_codetypeid
                                                                            || '/codeValue/'
                                                                            || l_codevaluecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 13 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_wbsid              varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_wbsid := l_top_obje.get_string('wbsId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_wbsid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_wbsid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_wbsid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_wbsid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_wbsid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_wbsid, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 14 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectid          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectid := l_top_obje.get_string('projectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_projectid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 15 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_activityid         varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_activityid := l_top_obje.get_string('activityId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_activityid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_activityid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_activityid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_activityid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_activityid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_activityid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 16 then
                declare
                    l_parameter             json_object_t := json_object_t();
                    l_param_obj             json_object_t;
                    l_activitycode          varchar2(1000);
                    l_includebaselinefields varchar2(1000);
                    l_projectcode           varchar2(1000);
                    l_workspacecode         varchar2(1000);
                    l_api_response          clob;
                    l_response_validator    json_object_t;
                    l_response_r            varchar2(250);
                    l_end_response          varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_activitycode := l_top_obje.get_string('activityCode');
                    l_includebaselinefields := l_top_obje.get_string('includeBaselineFields');
                    l_projectcode := l_top_obje.get_string('projectCode');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?activityCode='
                                        || l_activitycode
                                        || '&includeBaselineFields='
                                        || l_includebaselinefields
                                        || '&projectCode='
                                        || l_projectcode
                                        || '&workspaceCode='
                                        || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?activityCode='
                                            || l_activitycode
                                            || '&includeBaselineFields='
                                            || l_includebaselinefields
                                            || '&projectCode='
                                            || l_projectcode
                                            || '&workspaceCode='
                                            || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?activityCode='
                                                                               || l_activitycode
                                                                               || '&includeBaselineFields='
                                                                               || l_includebaselinefields
                                                                               || '&projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?activityCode='
                                                                                     || l_activitycode
                                                                                     || '&includeBaselineFields='
                                                                                     || l_includebaselinefields
                                                                                     || '&projectCode='
                                                                                     || l_projectcode
                                                                                     || '&workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?activityCode='
                                                                               || l_activitycode
                                                                               || '&includeBaselineFields='
                                                                               || l_includebaselinefields
                                                                               || '&projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?activityCode='
                                                                            || l_activitycode
                                                                            || '&includeBaselineFields='
                                                                            || l_includebaselinefields
                                                                            || '&projectCode='
                                                                            || l_projectcode
                                                                            || '&workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 17 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_activitycode       varchar2(1000);
                    l_projectid          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_activitycode := l_top_obje.get_string('activityCode');
                    l_projectid := l_top_obje.get_string('projectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectid
                                        || '/code/'
                                        || l_activitycode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectid
                                            || '/code/'
                                            || l_activitycode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_projectid
                                                                               || '/code/'
                                                                               || l_activitycode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_projectid
                                                                                     || '/code/'
                                                                                     || l_activitycode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_projectid
                                                                               || '/code/'
                                                                               || l_activitycode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_projectid
                                                                            || '/code/'
                                                                            || l_activitycode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 19 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_activityid         varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_activityid := l_top_obje.get_string('activityId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_activityid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_activityid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_activityid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_activityid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_activityid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_activityid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 20 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_activitycode       varchar2(1000);
                    l_projectcode        varchar2(1000);
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_activitycode := l_top_obje.get_string('activityCode');
                    l_projectcode := l_top_obje.get_string('projectCode');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?activityCode='
                                        || l_activitycode
                                        || '&projectCode='
                                        || l_projectcode
                                        || '&workspaceCode='
                                        || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?activityCode='
                                            || l_activitycode
                                            || '&projectCode='
                                            || l_projectcode
                                            || '&workspaceCode='
                                            || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?activityCode='
                                                                               || l_activitycode
                                                                               || '&projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?activityCode='
                                                                                     || l_activitycode
                                                                                     || '&projectCode='
                                                                                     || l_projectcode
                                                                                     || '&workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?activityCode='
                                                                               || l_activitycode
                                                                               || '&projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?activityCode='
                                                                            || l_activitycode
                                                                            || '&projectCode='
                                                                            || l_projectcode
                                                                            || '&workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 21 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectcode        varchar2(1000);
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectcode := l_top_obje.get_string('projectCode');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?projectCode='
                                        || l_projectcode
                                        || '&workspaceCode='
                                        || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?projectCode='
                                            || l_projectcode
                                            || '&workspaceCode='
                                            || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?projectCode='
                                                                                     || l_projectcode
                                                                                     || '&workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?projectCode='
                                                                            || l_projectcode
                                                                            || '&workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 22 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_relationshipid     varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_relationshipid := l_top_obje.get_string('relationshipId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_relationshipid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_relationshipid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_relationshipid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_relationshipid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_relationshipid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_relationshipid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 23 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_activityid         varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_activityid := l_top_obje.get_string('activityId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_activityid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_activityid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_activityid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_activityid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_activityid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_activityid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 381 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectid          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectid := l_top_obje.get_string('projectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_projectid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 382 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectriskid      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectriskid := l_top_obje.get_string('projectRiskId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectriskid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectriskid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_projectriskid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_projectriskid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_projectriskid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_projectriskid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 24 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_activityriskid     varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_activityriskid := l_top_obje.get_string('activityRiskId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_activityriskid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_activityriskid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_activityriskid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_activityriskid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_activityriskid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_activityriskid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 18 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?id=' || l_id,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?id=' || l_id,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?id='
                                                                               || l_id, systimestamp - interval '5' hour, l_method, l_api_name
                                                                               );

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?id='
                                                                                     || l_id, systimestamp - interval '5' hour, l_method
                                                                                     , l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?id='
                                                                               || l_id, systimestamp - interval '5' hour, l_method, l_api_name
                                                                               );

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?id='
                                                                            || l_id, systimestamp - interval '5' hour, l_method, l_api_name
                                                                            );

                        return to_clob('500');
                    end if;

                end;
            when 86 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?id=' || l_id,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?id=' || l_id,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?id='
                                                                               || l_id, l_method, systimestamp - interval '5' hour, l_api_name
                                                                               );

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?id='
                                                                                     || l_id, l_method, systimestamp - interval '5' hour
                                                                                     , l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?id='
                                                                               || l_id, systimestamp - interval '5' hour, l_method, l_api_name
                                                                               );

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?id='
                                                                            || l_id, l_method, systimestamp - interval '5' hour, l_api_name
                                                                            );

                        return to_clob('500');
                    end if;

                end;
            when 87 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?id=' || l_id,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?id=' || l_id,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?id='
                                                                               || l_id, systimestamp - interval '5' hour, l_method, l_api_name
                                                                               );

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?id='
                                                                                     || l_id, systimestamp - interval '5' hour, l_method
                                                                                     , l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?id='
                                                                               || l_id, systimestamp - interval '5' hour, l_method, l_api_name
                                                                               );

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?id='
                                                                            || l_id, systimestamp - interval '5' hour, l_method, l_api_name
                                                                            );

                        return to_clob('500');
                    end if;

                end;
            when 25 then
                declare
                    l_parameter              json_object_t := json_object_t();
                    l_param_obj              json_object_t;
                    l_applicationusergroupid varchar2(1000);
                    l_api_response           clob;
                    l_response_validator     json_object_t;
                    l_response_r             varchar2(250);
                    l_end_response           varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_applicationusergroupid := l_top_obje.get_string('applicationUserGroupId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_applicationusergroupid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_applicationusergroupid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_applicationusergroupid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_applicationusergroupid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_applicationusergroupid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_applicationusergroupid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 26 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_groupname          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_groupname := l_top_obje.get_string('groupName');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_groupname,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_groupname,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_groupname, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_groupname, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_groupname, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_groupname, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 27 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectid          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectid := l_top_obje.get_string('projectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_projectid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 28 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_assignmentid       varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_assignmentid := l_top_obje.get_string('assignmentId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_assignmentid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_assignmentid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_assignmentid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_assignmentid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_assignmentid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_assignmentid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 29 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_activityid         varchar2(1000);
                    l_assignmentcode     varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_activityid := l_top_obje.get_string('activityId');
                    l_assignmentcode := l_top_obje.get_string('assignmentCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_activityid
                                        || '/code/'
                                        || l_assignmentcode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_activityid
                                            || '/code/'
                                            || l_assignmentcode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_activityid
                                                                               || '/code/'
                                                                               || l_assignmentcode, systimestamp - interval '5' hour,
                                                                               l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_activityid
                                                                                     || '/code/'
                                                                                     || l_assignmentcode, systimestamp - interval '5'
                                                                                     hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_activityid
                                                                               || '/code/'
                                                                               || l_assignmentcode, systimestamp - interval '5' hour,
                                                                               l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_activityid
                                                                            || '/code/'
                                                                            || l_assignmentcode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 30 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_activityid         varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_activityid := l_top_obje.get_string('activityId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_activityid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_activityid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_activityid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_activityid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_activityid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_activityid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 31 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_assignmentcode     varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_assignmentcode := l_top_obje.get_string('assignmentCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_assignmentcode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_assignmentcode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_assignmentcode, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_assignmentcode, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_assignmentcode, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_assignmentcode, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 32 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_resourceid         varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_resourceid := l_top_obje.get_string('resourceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_resourceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_resourceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_resourceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_resourceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_resourceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_resourceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 33 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_resourcecode       varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_resourcecode := l_top_obje.get_string('resourceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_resourcecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_resourcecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_resourcecode, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_resourcecode, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_resourcecode, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_resourcecode, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 34 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_scenarioid         varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_scenarioid := l_top_obje.get_string('scenarioId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_scenarioid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_scenarioid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_scenarioid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_scenarioid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_scenarioid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_scenarioid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 35 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_scenarioid         varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_scenarioid := l_top_obje.get_string('scenarioId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_scenarioid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_scenarioid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_scenarioid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_scenarioid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_scenarioid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_scenarioid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 36 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_planperiod         varchar2(1000);
                    l_portfolioid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_planperiod := l_top_obje.get_string('planPeriod');
                    l_portfolioid := l_top_obje.get_string('portfolioId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?planPeriod='
                                        || l_planperiod
                                        || '&portfolioId='
                                        || l_portfolioid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?planPeriod='
                                            || l_planperiod
                                            || '&portfolioId='
                                            || l_portfolioid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?planPeriod='
                                                                               || l_planperiod
                                                                               || '&portfolioId='
                                                                               || l_portfolioid, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?planPeriod='
                                                                                     || l_planperiod
                                                                                     || '&portfolioId='
                                                                                     || l_portfolioid, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?planPeriod='
                                                                               || l_planperiod
                                                                               || '&portfolioId='
                                                                               || l_portfolioid, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?planPeriod='
                                                                            || l_planperiod
                                                                            || '&portfolioId='
                                                                            || l_portfolioid, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 37 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_planperiod         varchar2(1000);
                    l_portfolioname      varchar2(1000);
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_planperiod := l_top_obje.get_string('planPeriod');
                    l_portfolioname := l_top_obje.get_string('portfolioName');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?planPeriod='
                                        || l_planperiod
                                        || '&portfolioName='
                                        || l_portfolioname
                                        || '&workspaceCode='
                                        || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?planPeriod='
                                            || l_planperiod
                                            || '&portfolioName='
                                            || l_portfolioname
                                            || '&workspaceCode='
                                            || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?planPeriod='
                                                                               || l_planperiod
                                                                               || '&portfolioName='
                                                                               || l_portfolioname
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?planPeriod='
                                                                                     || l_planperiod
                                                                                     || '&portfolioName='
                                                                                     || l_portfolioname
                                                                                     || '&workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?planPeriod='
                                                                               || l_planperiod
                                                                               || '&portfolioName='
                                                                               || l_portfolioname
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?planPeriod='
                                                                            || l_planperiod
                                                                            || '&portfolioName='
                                                                            || l_portfolioname
                                                                            || '&workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 38 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_planperiod         varchar2(1000);
                    l_portfolioid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_planperiod := l_top_obje.get_string('planPeriod');
                    l_portfolioid := l_top_obje.get_string('portfolioId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?planPeriod='
                                        || l_planperiod
                                        || '&portfolioId='
                                        || l_portfolioid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?planPeriod='
                                            || l_planperiod
                                            || '&portfolioId='
                                            || l_portfolioid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?planPeriod='
                                                                               || l_planperiod
                                                                               || '&portfolioId='
                                                                               || l_portfolioid, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?planPeriod='
                                                                                     || l_planperiod
                                                                                     || '&portfolioId='
                                                                                     || l_portfolioid, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?planPeriod='
                                                                               || l_planperiod
                                                                               || '&portfolioId='
                                                                               || l_portfolioid, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?planPeriod='
                                                                            || l_planperiod
                                                                            || '&portfolioId='
                                                                            || l_portfolioid, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 39 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_planperiod         varchar2(1000);
                    l_portfolioname      varchar2(1000);
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_planperiod := l_top_obje.get_string('planPeriod');
                    l_portfolioname := l_top_obje.get_string('portfolioName');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?planPeriod='
                                        || l_planperiod
                                        || '&portfolioName='
                                        || l_portfolioname
                                        || '&workspaceCode='
                                        || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?planPeriod='
                                            || l_planperiod
                                            || '&portfolioName='
                                            || l_portfolioname
                                            || '&workspaceCode='
                                            || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?planPeriod='
                                                                               || l_planperiod
                                                                               || '&portfolioName='
                                                                               || l_portfolioname
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?planPeriod='
                                                                                     || l_planperiod
                                                                                     || '&portfolioName='
                                                                                     || l_portfolioname
                                                                                     || '&workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?planPeriod='
                                                                               || l_planperiod
                                                                               || '&portfolioName='
                                                                               || l_portfolioname
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?planPeriod='
                                                                            || l_planperiod
                                                                            || '&portfolioName='
                                                                            || l_portfolioname
                                                                            || '&workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 46 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_cbscode            varchar2(1000);
                    l_projecid           varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_cbscode := l_top_obje.get_string('cbsCode');
                    l_projecid := l_top_obje.get_string('projectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projecid
                                        || '/code/'
                                        || l_cbscode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projecid
                                            || '/code/'
                                            || l_cbscode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_projecid
                                                                               || '/code/'
                                                                               || l_cbscode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_projecid
                                                                                     || '/code/'
                                                                                     || l_cbscode, systimestamp - interval '5' hour, l_method
                                                                                     , l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_projecid
                                                                               || '/code/'
                                                                               || l_cbscode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_projecid
                                                                            || '/code/'
                                                                            || l_cbscode, systimestamp - interval '5' hour, l_method,
                                                                            l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 47 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projecid           varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projecid := l_top_obje.get_string('projectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projecid || '/totalCost',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projecid || '/totalCost',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_projecid
                                                                               || '/totalCost', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_projecid
                                                                                     || '/totalCost', systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_projecid
                                                                               || '/totalCost', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_projecid
                                                                            || '/totalCost', systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 48 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_cbssheetcodeid     varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_cbssheetcodeid := l_top_obje.get_string('cbsSheetCodeId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_cbssheetcodeid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_cbssheetcodeid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_cbssheetcodeid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_cbssheetcodeid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_cbssheetcodeid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_cbssheetcodeid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 49 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projecid           varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projecid := l_top_obje.get_string('projectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projecid || '/projectCostingSource',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projecid || '/projectCostingSource',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_projecid
                                                                               || '/projectCostingSource', systimestamp - interval '5'
                                                                               hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_projecid
                                                                                     || '/projectCostingSource', systimestamp - interval
                                                                                     '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_projecid
                                                                               || '/projectCostingSource', systimestamp - interval '5'
                                                                               hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_projecid
                                                                            || '/projectCostingSource', systimestamp - interval '5' hour
                                                                            , l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 50 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_cbstemplatecodeid  varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_cbstemplatecodeid := l_top_obje.get_string('cbsTemplateCodeId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_cbstemplatecodeid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_cbstemplatecodeid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_cbstemplatecodeid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_cbstemplatecodeid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_cbstemplatecodeid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_cbstemplatecodeid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 51 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_cbscode            varchar2(1000);
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_cbscode := l_top_obje.get_string('cbsCode');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?cbsCode='
                                        || l_cbscode
                                        || '&workspaceCode='
                                        || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?cbsCode='
                                            || l_cbscode
                                            || '&workspaceCode='
                                            || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?cbsCode='
                                                                               || l_cbscode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?cbsCode='
                                                                                     || l_cbscode
                                                                                     || '&workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?cbsCode='
                                                                               || l_cbscode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?cbsCode='
                                                                            || l_cbscode
                                                                            || '&workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 52 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectid          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectid := l_top_obje.get_string('projectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_projectid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 53 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectcode        varchar2(1000);
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectcode := l_top_obje.get_string('projectCode');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?projectCode='
                                        || l_projectcode
                                        || '&workspaceCode='
                                        || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?projectCode='
                                            || l_projectcode
                                            || '&workspaceCode='
                                            || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?projectCode='
                                                                                     || l_projectcode
                                                                                     || '&workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?projectCode='
                                                                            || l_projectcode
                                                                            || '&workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 54 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 55 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?workspaceCode=' || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?workspaceCode=' || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 56 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_cbssheetsegmentid  varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_cbssheetsegmentid := l_top_obje.get_string('cbsSheetSegmentId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_cbssheetsegmentid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_cbssheetsegmentid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_cbssheetsegmentid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_cbssheetsegmentid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_cbssheetsegmentid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_cbssheetsegmentid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 57 then
                declare
                    l_parameter            json_object_t := json_object_t();
                    l_param_obj            json_object_t;
                    l_cbstemplatesegmentid varchar2(1000);
                    l_api_response         clob;
                    l_response_validator   json_object_t;
                    l_response_r           varchar2(250);
                    l_end_response         varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_cbstemplatesegmentid := l_top_obje.get_string('cbsTemplateSegmentId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_cbstemplatesegmentid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_cbstemplatesegmentid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_cbstemplatesegmentid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_cbstemplatesegmentid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_cbstemplatesegmentid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_cbstemplatesegmentid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 58 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectid          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectid := l_top_obje.get_string('projectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_projectid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 59 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 40 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_calendarid         varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_calendarid := l_top_obje.get_string('calendarId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_calendarid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_calendarid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_calendarid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_calendarid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_calendarid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_calendarid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 41 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?workspaceCode=' || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?workspaceCode=' || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 42 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectid          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectid := l_top_obje.get_string('projectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_projectid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 43 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectcode        varchar2(1000);
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectcode := l_top_obje.get_string('projectCode');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?projectCode='
                                        || l_projectcode
                                        || '&workspaceCode='
                                        || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?projectCode='
                                            || l_projectcode
                                            || '&workspaceCode='
                                            || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?projectCode='
                                                                                     || l_projectcode
                                                                                     || '&workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?projectCode='
                                                                            || l_projectcode
                                                                            || '&workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 44 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 45 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 60 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_changerequestid    varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_changerequestid := l_top_obje.get_string('changeRequestId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_changerequestid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_changerequestid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_changerequestid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_changerequestid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_changerequestid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_changerequestid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 61 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_changerequestcode  varchar2(1000);
                    l_projectcode        varchar2(1000);
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_changerequestcode := l_top_obje.get_string('changeRequestCode');
                    l_projectcode := l_top_obje.get_string('projectCode');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?changeRequestCode='
                                        || l_changerequestcode
                                        || '&projectCode='
                                        || l_projectcode
                                        || '&workspaceCode='
                                        || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?changeRequestCode='
                                            || l_changerequestcode
                                            || '&projectCode='
                                            || l_projectcode
                                            || '&workspaceCode='
                                            || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?changeRequestCode='
                                                                               || l_changerequestcode
                                                                               || '&projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?changeRequestCode='
                                                                                     || l_changerequestcode
                                                                                     || '&projectCode='
                                                                                     || l_projectcode
                                                                                     || '&workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?changeRequestCode='
                                                                               || l_changerequestcode
                                                                               || '&projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?changeRequestCode='
                                                                            || l_changerequestcode
                                                                            || '&projectCode='
                                                                            || l_projectcode
                                                                            || '&workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 62 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectcode        varchar2(1000);
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectcode := l_top_obje.get_string('projectCode');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?projectCode='
                                        || l_projectcode
                                        || '&workspaceCode='
                                        || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?projectCode='
                                            || l_projectcode
                                            || '&workspaceCode='
                                            || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?projectCode='
                                                                                     || l_projectcode
                                                                                     || '&workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?projectCode='
                                                                            || l_projectcode
                                                                            || '&workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 63 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_codetypeid         varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_codetypeid := l_top_obje.get_string('codeTypeId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_codetypeid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_codetypeid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_codetypeid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_codetypeid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_codetypeid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_codetypeid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 64 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_codetypecode       varchar2(1000);
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_codetypecode := l_top_obje.get_string('codeTypeCode');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?codeTypeCode='
                                        || l_codetypecode
                                        || '&workspaceCode='
                                        || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?codeTypeCode='
                                            || l_codetypecode
                                            || '&workspaceCode='
                                            || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?codeTypeCode='
                                                                               || l_codetypecode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?codeTypeCode='
                                                                                     || l_codetypecode
                                                                                     || '&workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?codeTypeCode='
                                                                               || l_codetypecode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?codeTypeCode='
                                                                            || l_codetypecode
                                                                            || '&workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 65 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_type               varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_type := l_top_obje.get_string('type');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?type=' || l_type,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?type=' || l_type,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?type='
                                                                               || l_type, systimestamp - interval '5' hour, l_method,
                                                                               l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?type='
                                                                                     || l_type, systimestamp - interval '5' hour, l_method
                                                                                     , l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?type='
                                                                               || l_type, systimestamp - interval '5' hour, l_method,
                                                                               l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?type='
                                                                            || l_type, systimestamp - interval '5' hour, l_method, l_api_name
                                                                            );

                        return to_clob('500');
                    end if;

                end;
            when 66 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectid          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectid := l_top_obje.get_string('projectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_projectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_projectid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 67 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectcode        varchar2(1000);
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectcode := l_top_obje.get_string('projectCode');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?projectCode='
                                        || l_projectcode
                                        || '&workspaceCode='
                                        || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?projectCode='
                                            || l_projectcode
                                            || '&workspaceCode='
                                            || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?projectCode='
                                                                                     || l_projectcode
                                                                                     || '&workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?projectCode='
                                                                            || l_projectcode
                                                                            || '&workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 68 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 69 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?workspaceCode=' || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?workspaceCode=' || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 70 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_companyid          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_companyid := l_top_obje.get_string('companyId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_companyid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_companyid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_companyid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_companyid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_companyid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_companyid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 71 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_companyname        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_companyname := l_top_obje.get_string('companyName');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_companyname,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_companyname,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_companyname, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_companyname, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_companyname, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_companyname, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 72 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_companyname        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => null,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => null,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || null, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || null, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || null, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || null, systimestamp - interval '5' hour,
                                                           l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 73 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_companyname        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => null,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => null,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || null, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || null, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || null, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || null, systimestamp - interval '5' hour,
                                                           l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 74 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_companyname        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => null,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => null,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || null, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || null, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || null, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || null, systimestamp - interval '5' hour,
                                                           l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 75 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_columndefinitionid varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_columndefinitionid := l_top_obje.get_string('columnDefinitionId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_columndefinitionid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_columndefinitionid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_columndefinitionid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_columndefinitionid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_columndefinitionid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_columndefinitionid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 76 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 77 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 78 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 79 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 80 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 90 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_costcategoryname   varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_costcategoryname := l_top_obje.get_string('costCategoryName');
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid
                                        || '/name/'
                                        || l_costcategoryname,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid
                                            || '/name/'
                                            || l_costcategoryname,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_workspaceid
                                                                               || '/name/'
                                                                               || l_costcategoryname, systimestamp - interval '5' hour
                                                                               , l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_workspaceid
                                                                                     || '/name/'
                                                                                     || l_costcategoryname, systimestamp - interval '5'
                                                                                     hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_workspaceid
                                                                               || '/name/'
                                                                               || l_costcategoryname, systimestamp - interval '5' hour
                                                                               , l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_workspaceid
                                                                            || '/name/'
                                                                            || l_costcategoryname, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 91 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_costcategoryid     varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_costcategoryid := l_top_obje.get_string('costCategoryId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_costcategoryid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_costcategoryid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_costcategoryid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_costcategoryid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_costcategoryid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_costcategoryid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 92 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_costsheetid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_costsheetid := l_top_obje.get_string('costSheetId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_costsheetid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_costsheetid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_costsheetid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_costsheetid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_costsheetid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_costsheetid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 93 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_type               varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_type := l_top_obje.get_string('type');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?type=' || l_type,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?type=' || l_type,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?type='
                                                                               || l_type, systimestamp - interval '5' hour, l_method,
                                                                               l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?type='
                                                                                     || l_type, systimestamp - interval '5' hour, l_method
                                                                                     , l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?type='
                                                                               || l_type, systimestamp - interval '5' hour, l_method,
                                                                               l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?type='
                                                                            || l_type, systimestamp - interval '5' hour, l_method, l_api_name
                                                                            );

                        return to_clob('500');
                    end if;

                end;
            when 94 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 95 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_cbssheetcodeid     varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_cbssheetcodeid := l_top_obje.get_string('cbsSheetCodeId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_cbssheetcodeid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_cbssheetcodeid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_cbssheetcodeid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_cbssheetcodeid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_cbssheetcodeid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_cbssheetcodeid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 96 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_costcategoryname   varchar2(1000);
                    projectid            varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_costcategoryname := l_top_obje.get_string('costCategoryName');
                    projectid := l_top_obje.get_string('projectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_costcategoryname
                                        || '/project/'
                                        || projectid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_costcategoryname
                                            || '/project/'
                                            || projectid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_costcategoryname
                                                                               || '/project/'
                                                                               || projectid, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_costcategoryname
                                                                                     || '/project/'
                                                                                     || projectid, systimestamp - interval '5' hour, l_method
                                                                                     , l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_costcategoryname
                                                                               || '/project/'
                                                                               || projectid, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_costcategoryname
                                                                            || '/project/'
                                                                            || projectid, systimestamp - interval '5' hour, l_method,
                                                                            l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 199 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_costcategoryid     varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_costcategoryid := l_top_obje.get_string('costCategoryId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_costcategoryid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_costcategoryid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_costcategoryid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_costcategoryid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_costcategoryid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_costcategoryid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 200 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_costcategoryname   varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_costcategoryname := l_top_obje.get_string('costCategoryName');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_costcategoryname,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_costcategoryname,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_costcategoryname, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_costcategoryname, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_costcategoryname, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_costcategoryname, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 208 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_currencyid         varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_currencyid := l_top_obje.get_string('currencyId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_currencyid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_currencyid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_currencyid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_currencyid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_currencyid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_currencyid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 209 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_currencycode       varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_currencycode := l_top_obje.get_string('currencyCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_currencycode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_currencycode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_currencycode, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_currencycode, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_currencycode, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_currencycode, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 210 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_currencyname       varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_currencyname := l_top_obje.get_string('currencyName');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_currencyname,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_currencyname,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_currencyname, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_currencyname, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_currencyname, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_currencyname, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 211 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_currencyname       varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_currencyname := l_top_obje.get_string('currencyName');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => null,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => null,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || null, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || null, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || null, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || null, systimestamp - interval '5' hour,
                                                           l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 212 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 213 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_curveid            varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_curveid := l_top_obje.get_string('curveId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_curveid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_curveid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_curveid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_curveid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_curveid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_curveid, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 214 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_curvename          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_curvename := l_top_obje.get_string('curveName');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_curvename,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_curvename,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_curvename, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_curvename, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_curvename, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_curvename, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 215 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 216 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_curvename          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_curvename := l_top_obje.get_string('curveName');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid
                                        || '/name/'
                                        || l_curvename,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid
                                            || '/name/'
                                            || l_curvename,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_workspaceid
                                                                               || '/name/'
                                                                               || l_curvename, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_workspaceid
                                                                                     || '/name/'
                                                                                     || l_curvename, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_workspaceid
                                                                               || '/name/'
                                                                               || l_curvename, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_workspaceid
                                                                            || '/name/'
                                                                            || l_curvename, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 217 then
                declare
                    l_parameter             json_object_t := json_object_t();
                    l_param_obj             json_object_t;
                    l_customlogtypeobjectid varchar2(1000);
                    l_api_response          clob;
                    l_response_validator    json_object_t;
                    l_response_r            varchar2(250);
                    l_end_response          varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_customlogtypeobjectid := l_top_obje.get_string('customLogTypeObjectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_customlogtypeobjectid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_customlogtypeobjectid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_customlogtypeobjectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_customlogtypeobjectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_customlogtypeobjectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_customlogtypeobjectid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 218 then
                declare
                    l_parameter               json_object_t := json_object_t();
                    l_param_obj               json_object_t;
                    l_customlogtypeobjectname varchar2(1000);
                    l_programcode             varchar2(1000);
                    l_projectcode             varchar2(1000);
                    l_workspacecode           varchar2(1000);
                    l_api_response            clob;
                    l_response_validator      json_object_t;
                    l_response_r              varchar2(250);
                    l_end_response            varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_customlogtypeobjectname := l_top_obje.get_string('customLogTypeObjectName');
                    l_programcode := l_top_obje.get_string('programCode');
                    l_projectcode := l_top_obje.get_string('projectCode');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?customLogTypeObjectName='
                                        || l_customlogtypeobjectname
                                        || '&programCode='
                                        || l_programcode
                                        || '&projectCode='
                                        || l_projectcode
                                        || '&workspaceCode='
                                        || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?customLogTypeObjectName='
                                            || l_customlogtypeobjectname
                                            || '&programCode='
                                            || l_programcode
                                            || '&projectCode='
                                            || l_projectcode
                                            || '&workspaceCode='
                                            || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?customLogTypeObjectName='
                                                                               || l_customlogtypeobjectname
                                                                               || '&programCode='
                                                                               || l_programcode
                                                                               || '&projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?customLogTypeObjectName='
                                                                                     || l_customlogtypeobjectname
                                                                                     || '&programCode='
                                                                                     || l_programcode
                                                                                     || '&projectCode='
                                                                                     || l_projectcode
                                                                                     || '&workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?customLogTypeObjectName='
                                                                               || l_customlogtypeobjectname
                                                                               || '&programCode='
                                                                               || l_programcode
                                                                               || '&projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?customLogTypeObjectName='
                                                                            || l_customlogtypeobjectname
                                                                            || '&programCode='
                                                                            || l_programcode
                                                                            || '&projectCode='
                                                                            || l_projectcode
                                                                            || '&workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 219 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_programid          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_programid := l_top_obje.get_string('programId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_programid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_programid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_programid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_programid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_programid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_programid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 220 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_programid          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_programid := l_top_obje.get_string('projectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_programid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_programid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_programid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_programid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_programid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_programid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 221 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 222 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_programcode        varchar2(1000);
                    l_projectcode        varchar2(1000);
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_programcode := l_top_obje.get_string('programCode');
                    l_projectcode := l_top_obje.get_string('projectCode');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => '?programCode='
                                        || l_programcode
                                        || '&projectCode='
                                        || l_projectcode
                                        || '&workspaceCode='
                                        || l_workspacecode,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => '?programCode='
                                            || l_programcode
                                            || '&projectCode='
                                            || l_projectcode
                                            || '&workspaceCode='
                                            || l_workspacecode,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || '?programCode='
                                                                               || l_programcode
                                                                               || '&projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || '?programCode='
                                                                                     || l_programcode
                                                                                     || '&projectCode='
                                                                                     || l_projectcode
                                                                                     || '&workspaceCode='
                                                                                     || l_workspacecode, systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || '?programCode='
                                                                               || l_programcode
                                                                               || '&projectCode='
                                                                               || l_projectcode
                                                                               || '&workspaceCode='
                                                                               || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || '?programCode='
                                                                            || l_programcode
                                                                            || '&projectCode='
                                                                            || l_projectcode
                                                                            || '&workspaceCode='
                                                                            || l_workspacecode, systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 224 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_id,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_id,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_id, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_id, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_id, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_id, systimestamp - interval '5' hour,
                                                           l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 225 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_id,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_id,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_id, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_id, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_id, systimestamp - interval '5' hour
                                                           , l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_id, systimestamp - interval '5' hour,
                                                           l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 226 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_name               varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_name := l_top_obje.get_string('name');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_id
                                        || '/folderTemplate/'
                                        || l_name,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_id
                                            || '/folderTemplate/'
                                            || l_name,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_id
                                                                               || '/folderTemplate/'
                                                                               || l_name, systimestamp - interval '5' hour, l_method,
                                                                               l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_id
                                                                                     || '/folderTemplate/'
                                                                                     || l_name, systimestamp - interval '5' hour, l_method
                                                                                     , l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_id
                                                                               || '/folderTemplate/'
                                                                               || l_name, systimestamp - interval '5' hour, l_method,
                                                                               l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_id
                                                                            || '/folderTemplate/'
                                                                            || l_name, systimestamp - interval '5' hour, l_method, l_api_name
                                                                            );

                        return to_clob('500');
                    end if;

                end;
            when 227 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_id || '/version',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_id || '/version',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_id
                                                                               || '/version', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_id
                                                                                     || '/version', systimestamp - interval '5' hour,
                                                                                     l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_id
                                                                               || '/version', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_id
                                                                            || '/version', systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 228 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_id || '/allChildren',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_id || '/allChildren',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_id
                                                                               || '/allChildren', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_id
                                                                                     || '/version', systimestamp - interval '5' hour,
                                                                                     l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_id
                                                                               || '/allChildren', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_id
                                                                            || '/allChildren', systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 229 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_id || '/allChildren',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_id || '/allChildren',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_id
                                                                               || '/allChildren', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_id
                                                                                     || '/version', systimestamp - interval '5' hour,
                                                                                     l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_id
                                                                               || '/allChildren', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_id
                                                                            || '/allChildren', systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 230 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_id || '/files',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_id || '/files',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_id
                                                                               || '/files', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_id
                                                                                     || '/files', systimestamp - interval '5' hour, l_method
                                                                                     , l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_id
                                                                               || '/files', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_id
                                                                            || '/files', systimestamp - interval '5' hour, l_method, l_api_name
                                                                            );

                        return to_clob('500');
                    end if;

                end;
            when 231 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_id || '/files',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_id || '/files',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_id
                                                                               || '/files', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_id
                                                                                     || '/files', systimestamp - interval '5' hour, l_method
                                                                                     , l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_id
                                                                               || '/files', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_id
                                                                            || '/files', systimestamp - interval '5' hour, l_method, l_api_name
                                                                            );

                        return to_clob('500');
                    end if;

                end;
            when 232 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_id || '/childFolders',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_id || '/childFolders',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_id
                                                                               || '/childFolders', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_id
                                                                                     || '/childFolders', systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_id
                                                                               || '/childFolders', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_id
                                                                            || '/childFolders', systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 233 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_id || '/childFolders',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_id || '/childFolders',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_id
                                                                               || '/childFolders', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_id
                                                                                     || '/childFolders', systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_id
                                                                               || '/childFolders', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_id
                                                                            || '/childFolders', systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 234 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_id || '/references',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_id || '/references',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_id
                                                                               || '/references', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_id
                                                                                     || '/references', systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_id
                                                                               || '/references', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_id
                                                                            || '/references', systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 235 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_version            varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_version := l_top_obje.get_string('version');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_id
                                        || '/version/'
                                        || l_version
                                        || '/annotations',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_id
                                            || '/version/'
                                            || l_version
                                            || '/annotations',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_id
                                                                               || '/version/'
                                                                               || l_version
                                                                               || '/annotations', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_id
                                                                                     || '/version/'
                                                                                     || l_version
                                                                                     || '/annotations', systimestamp - interval '5' hour
                                                                                     , l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_id
                                                                               || '/version/'
                                                                               || l_version
                                                                               || '/annotations', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_id
                                                                            || '/version/'
                                                                            || l_version
                                                                            || '/annotations', systimestamp - interval '5' hour, l_method
                                                                            , l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 236 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_type               varchar2(1000);
                    l_workspacecode      varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_type := l_top_obje.get_string('type');
                    l_workspacecode := l_top_obje.get_string('workspaceCode');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspacecode
                                        || '/'
                                        || l_type
                                        || '/search',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspacecode
                                            || '/'
                                            || l_type
                                            || '/search',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_workspacecode
                                                                               || '/'
                                                                               || l_type
                                                                               || '/search', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_workspacecode
                                                                                     || '/'
                                                                                     || l_type
                                                                                     || '/search', systimestamp - interval '5' hour, l_method
                                                                                     , l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_workspacecode
                                                                               || '/'
                                                                               || l_type
                                                                               || '/search', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_workspacecode
                                                                            || '/'
                                                                            || l_type
                                                                            || '/search', systimestamp - interval '5' hour, l_method,
                                                                            l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 237 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_portfolioid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_portfolioid := l_top_obje.get_string('portfolioId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_portfolioid || '/root',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_portfolioid || '/root',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_portfolioid
                                                                               || '/root', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_portfolioid
                                                                                     || '/root', systimestamp - interval '5' hour, l_method
                                                                                     , l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_portfolioid
                                                                               || '/root', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_portfolioid
                                                                            || '/root', systimestamp - interval '5' hour, l_method, l_api_name
                                                                            );

                        return to_clob('500');
                    end if;

                end;
            when 238 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_projectid          varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_projectid := l_top_obje.get_string('projectId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_projectid || '/root',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_projectid || '/root',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_projectid
                                                                               || '/root', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_projectid
                                                                                     || '/root', systimestamp - interval '5' hour, l_method
                                                                                     , l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_projectid
                                                                               || '/root', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_projectid
                                                                            || '/root', systimestamp - interval '5' hour, l_method, l_api_name
                                                                            );

                        return to_clob('500');
                    end if;

                end;
            when 239 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_id                 varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_id := l_top_obje.get_string('id');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_id || '/root',
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_id || '/root',
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: '
                                                                               || l_id
                                                                               || '/root', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: '
                                                                                     || l_id
                                                                                     || '/root', systimestamp - interval '5' hour, l_method
                                                                                     , l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: '
                                                                               || l_id
                                                                               || '/root', systimestamp - interval '5' hour, l_method
                                                                               , l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: '
                                                                            || l_id
                                                                            || '/root', systimestamp - interval '5' hour, l_method, l_api_name
                                                                            );

                        return to_clob('500');
                    end if;

                end;
            when 240 then
                declare
                    l_parameter                         json_object_t := json_object_t();
                    l_param_obj                         json_object_t;
                    l_documentfolderstructuretemplateid varchar2(1000);
                    l_api_response                      clob;
                    l_response_validator                json_object_t;
                    l_response_r                        varchar2(250);
                    l_end_response                      varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_documentfolderstructuretemplateid := l_top_obje.get_string('documentFolderStructureTemplateId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_documentfolderstructuretemplateid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_documentfolderstructuretemplateid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_documentfolderstructuretemplateid,
                                                           systimestamp - interval '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_documentfolderstructuretemplateid
                                                           , systimestamp - interval '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_documentfolderstructuretemplateid,
                                                           systimestamp - interval '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_documentfolderstructuretemplateid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 241 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 242 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_templatename       varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_templatename := l_top_obje.get_string('templateName');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_templatename,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_templatename,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_templatename, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_templatename, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_templatename, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_templatename, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 243 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_workspaceid        varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_workspaceid := l_top_obje.get_string('workspaceId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_workspaceid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_workspaceid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_workspaceid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_workspaceid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 244 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_exchangerateid     varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_exchangerateid := l_top_obje.get_string('exchangeRateId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_exchangerateid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_exchangerateid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_exchangerateid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_exchangerateid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_exchangerateid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_exchangerateid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
            when 245 then
                declare
                    l_parameter          json_object_t := json_object_t();
                    l_param_obj          json_object_t;
                    l_currencyid         varchar2(1000);
                    l_api_response       clob;
                    l_response_validator json_object_t;
                    l_response_r         varchar2(250);
                    l_end_response       varchar2(1000);
                begin
                    l_param_obj := json_object_t.parse(iv_param_json);
                    l_parameter.put('Parameters', l_param_obj);
                    l_currencyid := l_top_obje.get_string('currencyId');
                    l_api_response := vl_pkg_rest_services.vl_fn_rest_services(
                        iv_filterurl     => l_currencyid,
                        iv_bodyrequest   => null,
                        iv_projectid     => null,
                        iv_alias         => l_application_name,
                        iv_company       => iv_company_name,
                        iv_methodcontext => iv_cod_context,
                        iv_environment   => iv_environment
                    );

                    if l_api_response not in ( '404', '204', '500' ) then
                        l_end_response := vl_pkg_rest_services.vl_sp_json_mgmn(
                            iv_filterurl     => l_currencyid,
                            iv_bodyrequest   => null,
                            iv_projectid     => null,
                            iv_alias         => l_application_name,
                            iv_company       => iv_company_name,
                            iv_methodcontext => iv_cod_context,
                            iv_environment   => iv_environment
                        );

                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 200
                        ,
                                                           'Uso de la API: '
                                                           || l_api_name
                                                           || ' , SOLICITADO POR: '
                                                           || iv_company_name, 'Parameters: ' || l_currencyid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return l_end_response;
                    elsif l_api_response = to_clob('404') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 404
                        ,
                                                           'Parametro no es v?lido', 'Parameters: ' || l_currencyid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('404');
                    elsif l_api_response = to_clob('204') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'No hay contenido', 'Parameters: ' || l_currencyid, systimestamp - interval
                                                           '5' hour, l_method, l_api_name);

                        return to_clob('204');
                    elsif l_api_response = to_clob('500') then
                        vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 204
                        ,
                                                           'Error interno', 'Parameters: ' || l_currencyid, systimestamp - interval '5'
                                                           hour, l_method, l_api_name);

                        return to_clob('500');
                    end if;

                end;
        end case;

    exception
        when others then
            if sqlcode = -40441 then
                vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, 40441,
                                                   'Item de entrada no es valido', 'Parameters: ' || iv_param_json, systimestamp - interval
                                                   '5' hour, l_method, l_api_name);

                return to_clob(40441);
            else
                vl_pkg_rest_services.vl_audit_logs(iv_cod_context, iv_company_name, l_application_name, 'T-' || l_audit_log, sqlcode,
                                                   'Error inesperado : Mensaje'
                                                   || sqlcode
                                                   || sqlerrm
                                                   || ' Programa: '
                                                   || $$plsql_unit
                                                   || ' L?nea '
                                                   || $$plsql_line
                                                   || ' Backtrace: '
                                                   || dbms_utility.format_error_backtrace, 'Parameters: ' || iv_param_json, systimestamp - interval
                                                   '5' hour, l_method, l_api_name);
            end if;
    end vl_extract_api_response;

    function vl_sp_json_mgmn (
        iv_filterurl     in varchar2 default null,
        iv_bodyrequest   in varchar2 default null,
        iv_projectid     in varchar2 default null,
        iv_alias         in varchar2,
        iv_company       in varchar2,
        iv_methodcontext in number,
        iv_environment   in number
    ) return varchar2 as

        pragma autonomous_transaction;
        cursor c_getdocjson (
            vci_name varchar2
        ) is
        select
            json_name
        from
            vl_json_documents
        where
            json_name = vci_name;

        cursor c_getapiresponse (
            vci_filterurl     varchar2,
            vci_bodyrequest   varchar2,
            vci_projectid     varchar2,
            vci_alias         varchar2,
            vci_company       varchar2,
            vci_methodcontext number,
            vci_environment   number
        ) is
        select
            vl_pkg_rest_services.vl_fn_rest_services(
                iv_filterurl     => vci_filterurl,
                iv_bodyrequest   => vci_bodyrequest,
                iv_projectid     => vci_projectid,
                iv_alias         => vci_alias,
                iv_company       => vci_company,
                iv_methodcontext => vci_methodcontext,
                iv_environment   => vci_environment
            ) valor,
            name
        from
            vl_path_contexts
        where
            id_vl_path_context = vci_methodcontext;

        l_getdocjson              c_getdocjson%rowtype;
        l_exists_c_getdocjson     boolean;
        l_getapiresponse          c_getapiresponse%rowtype;
        l_exists_c_getapiresponse boolean;
        json_validator            json_object_t;
        l_project_value           varchar2(1000);
        l_bp_value                varchar2(1000);
        l_bp_name                 vl_json_documents.bp_name%type;
        json_syntax_error exception;
        l_name_validator          varchar2(120);
        l_api_name                varchar2(100);
        l_view_name               varchar2(100);
        l_bp_name_n               varchar2(120);
        pragma exception_init ( json_syntax_error, -40441 );
    begin
        case
            when
                iv_alias = 'OPU'
                and iv_filterurl is not null
            then
                if
                    instr(iv_filterurl, '?projectnumber=') > 0
                    and iv_bodyrequest is null
                then
                    l_project_value := substr(iv_filterurl,
                                              instr(iv_filterurl, '?projectnumber=') + length('?projectnumber='));

                    if instr(l_project_value, '&') > 0 then
                        l_project_value := substr(l_project_value,
                                                  1,
                                                  instr(l_project_value, '&') - 1);

                    end if;

                elsif
                    instr(iv_filterurl, '?input=') > 0
                    and iv_bodyrequest is null
                then
                    l_bp_value := substr(iv_filterurl,
                                         instr(iv_filterurl, '?input=') + length('?input='));

                    json_validator := json_object_t(l_bp_value);
                    l_bp_name := json_validator.get_string('bpname');
                    l_project_value := substr(iv_filterurl,
                                              1,
                                              instr(iv_filterurl, '?input=') - 1);

                elsif
                    iv_filterurl is not null
                    and iv_bodyrequest is not null
                    and iv_methodcontext != 165
                then
                    json_validator := json_object_t(iv_bodyrequest);
                    l_bp_name := json_validator.get_string('bpname');
                    l_project_value := iv_filterurl;
                elsif instr(iv_filterurl, '?projectnumber=') > 0 then
                    l_project_value := iv_filterurl;
                else
                    l_project_value := null;
                end if;
            else
                null;
        end case;

        select
            name
        into l_api_name
        from
            vl_path_contexts
        where
            id_vl_path_context = iv_methodcontext;

        l_name_validator := l_api_name;
        l_view_name := substr(l_name_validator, 1, 1);
        for i in 2..length(l_name_validator) loop
            if substr(l_name_validator, i - 1, 1) = ' ' then
                l_view_name := l_view_name
                               || substr(l_name_validator, i, 1);
            end if;
        end loop;

        l_bp_name := upper(replace(l_bp_name, '/', '-'));
        l_view_name := l_view_name
                       || iv_methodcontext
                       || iv_company
                       || upper(replace(l_project_value, ' ', ''))
                       || upper(replace(l_bp_name, ' ', ''));

        l_view_name := upper(l_view_name);
        open c_getdocjson(l_view_name);
        fetch c_getdocjson into l_getdocjson;
        l_exists_c_getdocjson := c_getdocjson%found;
        close c_getdocjson;
        open c_getapiresponse(iv_filterurl, iv_bodyrequest, iv_projectid, iv_alias, iv_company,
                              iv_methodcontext, iv_environment);
        fetch c_getapiresponse into l_getapiresponse;
        l_exists_c_getapiresponse := c_getapiresponse%found;
        close c_getapiresponse;
        if
            l_exists_c_getdocjson = false
            and l_exists_c_getapiresponse
        then
            insert into vl_json_documents (
                json_name,
                id_vl_path_context,
                json_file,
                project_id,
                bp_name
            ) values
                ( l_view_name,
                  iv_methodcontext,
                  l_getapiresponse.valor,
                  l_project_value,
                  l_bp_name );

            commit;
            declare
                l_dg           clob;
                l_view_c       clob;
                l_new_c        clob;
                l_name_conflic boolean;
            begin
                l_name_conflic := true;
                select
                    json_dataguide(json_file, dbms_json.format_hierarchical)
                into l_dg
                from
                    vl_json_documents
                where
                    json_name = l_view_name;

                select
                    dbms_json.get_view_sql(l_view_name, 'VL_JSON_DOCUMENTS', 'JSON_FILE', l_dg,
                                           resolvenameconflicts => l_name_conflic)
                into l_view_c
                from
                    dual;

                l_new_c := l_view_c
                           || ' WHERE "RT"."JSON_NAME" = '''
                           || l_view_name
                           || '''';
                execute immediate l_new_c;
            end;

        else
            update vl_json_documents
            set
                json_file = l_getapiresponse.valor
            where
                json_name = l_view_name;

            commit;
            declare
                l_dg           clob;
                l_view_c       clob;
                l_new_c        clob;
                l_name_conflic boolean;
            begin
                l_name_conflic := true;
                select
                    json_dataguide(json_file, dbms_json.format_hierarchical)
                into l_dg
                from
                    vl_json_documents
                where
                    json_name = l_view_name;

                select
                    dbms_json.get_view_sql(l_view_name, 'VL_JSON_DOCUMENTS', 'JSON_FILE', l_dg,
                                           resolvenameconflicts => l_name_conflic)
                into l_view_c
                from
                    dual;

                l_new_c := l_view_c
                           || ' WHERE "RT"."JSON_NAME" = '''
                           || l_view_name
                           || '''';
                execute immediate l_new_c;
            end;

        end if;

        return upper(l_view_name);
    exception
        when json_syntax_error then
            dbms_output.put_line('Json en formato invalido');
    end vl_sp_json_mgmn;

    procedure vl_audit_logs (
        iv_path_context       in number,
        iv_company_shortname  in varchar2,
        iv_aplication         in varchar2,
        iv_vl_audit_log       in varchar2,
        iv_vl_status_code     in number,
        iv_vl_log_description in varchar2,
        iv_vl_parameters      in clob,
        iv_timestamp          in timestamp,
        iv_vl_method          in varchar2,
        iv_name_api           in varchar2
    ) as
    begin
        insert into vl_logs (
            id_vl_path_context,
            company_shortname,
            vl_audit_log,
            vl_status_code,
            vl_log_description,
            vl_parameters,
            vl_timestamp,
            vl_method,
            vl_aplication,
            vl_name_api
        ) values
            ( iv_path_context,
              iv_company_shortname,
              iv_vl_audit_log,
              iv_vl_status_code,
              iv_vl_log_description,
              iv_vl_parameters,
              iv_timestamp,
              iv_vl_method,
              iv_aplication,
              iv_name_api );

        commit;
    end;

  -- Funci®n para validar si un URL principal de valido o no retornando un boolean
    function vl_fn_validate_source (
        iv_alias       in varchar2,  -- Alias de la compaia
        iv_company     in varchar2,  -- Compaia
        iv_environment in number,    -- Enviroment
        iv_user_base64 in varchar2,  -- Usuario en Base64
        iv_endpoint    in varchar2
    )  -- URL
     return boolean as

        pragma autonomous_transaction;

      -- Se obtiene el end point completo (URL principal ingresado por el usuario mas path context almacenado en la BD) mediante un cursor con parametros.
        cursor c_geturl (
            iv_alias varchar2
        ) is
        select
            iv_endpoint || pc.path_context as source_url,
            ct.call_name
        from
                 vl_source_applications sa
            join vl_source_collections sc on sa.id_vl_source_application = sc.id_vl_source_application
            join vl_path_contexts      pc on sc.id_vl_source_collection = pc.id_vl_source_collection
            left join vl_call_types         ct on pc.id_vl_call_type = ct.id_vl_call_type
        where
                pc.name = 'Get Token'
            and sa.alias = iv_alias;

      -- Variables
        l_geturl          c_geturl%rowtype;
        l_resp_buffer     clob;             -- Variable en el cual se almacenar~ el buffer de la respuesta
        l_status          varchar2(100);    -- Variable en el cual se almacenar~ el status de la respuesta en el caso de OPU
        l_access_token    clob;             -- Variable en el cual se almacenar~ el token de acceso de la respuesta en el caso de OPC
        l_exists_c_geturl boolean;          -- Variable con el cual se validar~ si se encontro el endpoint
    begin
        open c_geturl(iv_alias);
        fetch c_geturl into l_geturl;
        l_exists_c_geturl := c_geturl%found;
        close c_geturl;
        if l_exists_c_geturl then -- Se valida si existe el end point completo

            apex_web_service.g_request_headers.delete();
            apex_web_service.g_request_headers(1).name := 'Authorization';
            apex_web_service.g_request_headers(1).value := 'Basic ' || iv_user_base64;
            l_resp_buffer := apex_web_service.make_rest_request(
                p_url         => utl_url.escape(l_geturl.source_url, false, 'UTF-8'),
                p_http_method => l_geturl.call_name
            );

          -- Se valida el caso de OPU con el status de 200 lo que nos indica que la conexci®n fue exitosa
            if iv_alias = 'OPU' then
                if l_resp_buffer is not null then
                    l_status := json_object_t(l_resp_buffer).get_string('status');
                    return l_status = '200';
                else
                    return false; -- Buffer vacio
                end if;

          -- Se valida el caso de OPC con el access token lo que nos indica que la conexci®n fue exitosa
            elsif iv_alias = 'OPC' then
                if l_resp_buffer is not null then
                    l_access_token := json_object_t(l_resp_buffer).get_string('accessToken');
                    return l_access_token is not null;
                else
                    return false; -- Buffer vacio
                end if;
            else
                return false; -- Alias no reconocido
            end if;

        else
            return false; -- No se encontr® la URL
        end if;

    exception
        when others then
            declare
                l_error_message clob; -- Se almacena la excepci®n en una variable en caso de necesitare en un futuro
            begin
                l_error_message := to_clob('Error: '
                                           || to_char(sqlcode)
                                           || ' - '
                                           || sqlerrm
                                           || ' Backtrace: ' || dbms_utility.format_error_backtrace);

                return false; -- De presentarse algun error se retornara falso (La conexci®n no fue exitosa)
            end;
    end vl_fn_validate_source;

end vl_pkg_rest_services;
/


-- sqlcl_snapshot {"hash":"27e87ed49c2bd965250b9e3d1dcfcddd5039b4da","type":"PACKAGE_BODY","name":"VL_PKG_REST_SERVICES","schemaName":"VERANOLINK","sxml":""}