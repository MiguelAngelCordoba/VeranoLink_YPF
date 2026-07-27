-- liquibase formatted sql
-- changeset VERANOLINK:1785188144900 stripComments:false  logicalFilePath:base-release\veranolink\package_bodies\vl_pkg_sync_tables.sql
-- sqlcl_snapshot db/src/database/veranolink/package_bodies/vl_pkg_sync_tables.sql:null:5cfdd74fe1cd1cee2d245f631152f4bff42f7331:create

create or replace package body veranolink.vl_pkg_sync_tables as

    procedure sp_create_table_job (
        job_name in varchar2
    ) as
    begin
        null;
    end sp_create_table_job;

    procedure sp_sync_table (
        iv_table_name in varchar2,
        iv_user_id    in number,
        iv_company    in varchar2
    ) is

        l_response_validator    json_object_t;
        l_response              clob;
        l_end_response          clob;
        cursor c_get_table_info is
        select
            vst.json_request,
            api_id,
            vst.request_env,
            vst.short_company,
            vst.table_query
        from
            vl_saved_tables vst
        where
                vst.short_company = iv_company
            and vst.table_name = iv_table_name
            and vst.id_user = iv_user_id;

        v_get_table_indo        c_get_table_info%rowtype;
        v_find_table_info       boolean := false;
        l_response_r            number;
        v_value_aplication_name varchar2(100);
        v_view_response         clob;
        v_is_number             boolean;
        v_query_drop            varchar2(4000);
    begin
        open c_get_table_info;
        fetch c_get_table_info into v_get_table_indo;
        v_find_table_info := c_get_table_info%found;
        close c_get_table_info;
        if v_find_table_info then
            select
                vsa.alias
            into v_value_aplication_name
            from
                     vl_path_contexts vpc
                inner join vl_source_collections  vsc on vpc.id_vl_source_collection = vsc.id_vl_source_collection
                inner join vl_source_applications vsa on vsc.id_vl_source_application = vsa.id_vl_source_application
                                                         and vpc.id_vl_path_context = v_get_table_indo.api_id;

            v_view_response := vl_pkg_rest_services.vl_extract_api_response(
                iv_param_json   => v_get_table_indo.json_request,
                iv_cod_context  => v_get_table_indo.api_id,
                iv_company_name => v_get_table_indo.short_company,
                iv_environment  => v_get_table_indo.request_env
            );

            if regexp_like(
                dbms_lob.substr(v_view_response, 4000, 1),
                '^\d+$'
            ) then
                v_is_number := true;  -- Es un número
            else
                v_is_number := false;  -- Es texto
            end if;

            if not v_is_number then
                v_query_drop := 'DROP TABLE "'
                                || v_get_table_indo.short_company
                                || '"."'
                                || iv_table_name
                                || '"';

                execute immediate v_query_drop;
            end if;

        end if;

    end sp_sync_table;

    function create_job_for_sync_tables (    
      -- Datos del job
        v_job_name       in varchar2,
        v_new_state      in varchar2,
        v_new_interval   in varchar2,
        v_job_interval   in number,
        v_job_comments   in varchar2,  

      -- Variables necesarias para ejecución
        get_id_table     in number,
        get_company      in number,
        get_company_name in varchar2
    ) return number is
      -- Variables internas
        get_alias        varchar2(1500 char);
        enviroment       number;
        encode64         varchar2(15000 char);
        get_url          varchar2(1500 char);
        validator        boolean;

      -- Variables usadas para invocar el procedimiento de actualización JSON
        get_response     varchar2(1000 char);
        get_param_json   clob;
        get_api_id       number;
        get_view_name    varchar2(1000 char);
        get_table_name   varchar2(4000 char);
        get_query_create clob;
    begin
      -- Obtener el alias de la aplicación fuente
        select
            vsa.alias
        into get_alias
        from
            vl_source_applications vsa
        where
            vsa.id_vl_source_application = (
                select
                    application
                from
                    vl_saved_tables
                where
                    vl_id_saved_table = get_id_table
            )
        fetch first 1 row only;

      -- Obtener el ambiente de la aplicación fuente
        select
            request_env
        into enviroment
        from
            vl_saved_tables
        where
            vl_id_saved_table = get_id_table
        fetch first 1 row only;

      -- Obtener encode64 y link principal
        select
            vsc.source_authentication,
            vsc.source_url
        into
            encode64,
            get_url
        from
                 vl_sources vsc
            inner join vl_companies_source_applications vsca on vsc.id_vl_company_application = vsca.id_vl_company_application
        where
                vsc.id_vl_type_environment = enviroment
            and vsca.vl_id_company = get_company
            and vsca.id_vl_source_application = (
                select
                    application
                from
                    vl_saved_tables
                where
                    vl_id_saved_table = get_id_table
            )
        fetch first 1 row only;

      -- Validación de credenciales
        validator := vl_pkg_rest_services.vl_fn_validate_source(get_alias, get_company_name, enviroment, encode64, get_url);
        if not validator then
            return 4;
        end if;

      -- Obtener parámetros JSON usados en la consulta
        select
            json_request,
            api_id,
            view_name,
            table_name,
            query_create
        into
            get_param_json,
            get_api_id,
            get_view_name,
            get_table_name,
            get_query_create
        from
            vl_saved_tables
        where
            vl_id_saved_table = get_id_table
        fetch first 1 row only;

      -- Llamar a la API
        get_response := vl_pkg_rest_services.vl_extract_api_response(
            iv_param_json   => get_param_json,
            iv_cod_context  => get_api_id,
            iv_company_name => get_company_name,
            iv_environment  => enviroment
        );

        if get_response <> get_view_name then
            return 3;
        end if;

      -- Crear el job
        dbms_scheduler.create_job(
            job_name        => v_job_name,
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'DECLARE
                                v_response CLOB;
                                v_cols CLOB;
                                v_sql  CLOB;
                            BEGIN
                                v_response := VL_PKG_REST_SERVICES.VL_EXTRACT_API_RESPONSE(
                                                iv_param_json  => '''
                          || get_param_json
                          || ''',
                                                iv_cod_context => '''
                          || get_api_id
                          || ''',
                                                iv_company_name => '''
                          || get_company_name
                          || ''',
                                                iv_environment  => '''
                          || enviroment
                          || ''');

                                IF v_response = '''
                          || get_view_name
                          || ''' THEN

                                  EXECUTE IMMEDIATE '
                          || '''DROP TABLE '
                          || get_company_name
                          || '.'
                          || get_table_name
                          || ''' ;

                                  v_sql := '
                          || chr(39)
                          || 'CREATE TABLE '
                          || get_company_name
                          || '.'
                          || get_table_name
                          || ' AS ( '
                          || get_query_create
                          || ' )'
                          || chr(39)
                          || ';

                                  EXECUTE IMMEDIATE v_sql;

                                  EXECUTE IMMEDIATE '''
                          || 'commit'
                          || ''' ;

                                ELSE
                                  DBMS_OUTPUT.PUT_LINE('
                          || chr(39)
                          || ' Error - La vista retornada es '
                          || chr(39)
                          || '|| v_response || '
                          || chr(39)
                          || ' y la vista esperada era '
                          || get_view_name
                          || chr(39)
                          || ');
                                END IF;

                            EXCEPTION
                                WHEN OTHERS THEN

                                    DBMS_OUTPUT.PUT_LINE('
                          || chr(39)
                          || ' Error: '
                          || chr(39)
                          || '|| SQLERRM ||'
                          || chr(39)
                          || ' Código: '
                          || chr(39)
                          || '|| SQLCODE'
                          || ');

                            END;',
            start_date      => systimestamp + interval '1' minute,
            repeat_interval => v_new_interval,
            end_date        => null,
            enabled         =>(v_new_state = 'TRUE'),
            auto_drop       => false,
            comments        => v_job_comments
        );

        update vl_saved_tables
        set
            is_sync = 'Si'
        where
            get_id_table = vl_id_saved_table;

        commit;
        return 6;
    exception
        when value_error then
            return 3;
        when others then
            return 3;
    end create_job_for_sync_tables;

end vl_pkg_sync_tables;
/

