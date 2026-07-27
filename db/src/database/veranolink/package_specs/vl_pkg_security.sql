create or replace package veranolink.vl_pkg_security is
    function autentica (
        p_user_name varchar2,
        p_password  varchar2
    ) return boolean;

    procedure logeado (
        p_user_name varchar2,
        p_password  varchar2,
        p_app_id    number
    );

    function api_tables_verification (
        p_user_query   varchar2,
        p_company_name varchar2,
        p_query_id     varchar2,
        p_user_id      number
    ) return varchar2;

end vl_pkg_security;
/


-- sqlcl_snapshot {"hash":"7c2adba91a6382cd75d542c8d4370993d2396ff3","type":"PACKAGE_SPEC","name":"VL_PKG_SECURITY","schemaName":"VERANOLINK","sxml":""}