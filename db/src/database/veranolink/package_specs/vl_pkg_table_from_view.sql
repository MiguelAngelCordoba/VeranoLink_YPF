create or replace package veranolink.vl_pkg_table_from_view is
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
    );

end vl_pkg_table_from_view;
/


-- sqlcl_snapshot {"hash":"07a61b1886df7c1adca75279915e3716369fec94","type":"PACKAGE_SPEC","name":"VL_PKG_TABLE_FROM_VIEW","schemaName":"VERANOLINK","sxml":""}