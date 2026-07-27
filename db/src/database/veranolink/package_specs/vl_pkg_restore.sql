create or replace package veranolink.vl_pkg_restore is
    function vl_restore (
        p_email in varchar2
    ) return boolean;

    procedure update_password (
        p_password varchar2,
        p_email    varchar2
    );

end vl_pkg_restore;
/


-- sqlcl_snapshot {"hash":"debf24befe944ecb5471b5d537149ea58256345c","type":"PACKAGE_SPEC","name":"VL_PKG_RESTORE","schemaName":"VERANOLINK","sxml":""}