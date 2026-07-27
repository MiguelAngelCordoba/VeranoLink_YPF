create or replace package body veranolink.vl_pkg_table_from_view as

    procedure create_table (
        cod_api              number,
        user_name            varchar2,
        table_name           varchar2,
        query_view           clob,
        name_view_to_replace varchar2,
        user_id              number,
        v_main_request_json  clob,
        v_main_environment   number,
        v_application        number,
        v_view_source        varchar2
    ) as

        v_query_create     clob := to_clob(query_view);
        name_api_from_code varchar(1000);
        v_query            clob;
        v_select_part      clob;
        v_insert_query     clob;
    begin
        v_query := 'CREATE TABLE "'
                   || user_name
                   || '"."'
                   || table_name
                   || '" AS ('
                   || query_view
                   || ')';

        execute immediate v_query;
        v_insert_query := replace(query_view, '"VERANOLINK"."'
                                              || name_view_to_replace
                                              || '"', '"'
                                                      || user_name
                                                      || '"."'
                                                      || table_name
                                                      || '"');

        select
            name
        into name_api_from_code
        from
            vl_path_contexts vpc
        where
            vpc.id_vl_path_context = cod_api;

        insert into vl_saved_tables (
            name_api,
            short_company,
            table_name,
            table_query,
            id_user,
            json_request,
            request_env,
            api_id,
            application,
            view_name,
            query_create
        ) values
            ( name_api_from_code,
              user_name,
              table_name,
              v_insert_query,
              user_id,
              v_main_request_json,
              v_main_environment,
              cod_api,
              v_application,
              v_view_source,
              v_query_create );

    end;

end vl_pkg_table_from_view;
/


-- sqlcl_snapshot {"hash":"9a83f10fc3b0602e785f4f3ac7d093d5b161551c","type":"PACKAGE_BODY","name":"VL_PKG_TABLE_FROM_VIEW","schemaName":"VERANOLINK","sxml":""}