create or replace package veranolink.vl_pkg_crud_company is
    procedure new_company (
        names       varchar2,
        country     number,
        short_names varchar2
    );

    procedure update_company (
        p_name          varchar2,
        p_country       number,
        p_vl_id_company number,
        short_names     varchar2
    );

    procedure delete_company (
        p_vl_id_company number,
        short_names     varchar2
    );

end vl_pkg_crud_company;
/


-- sqlcl_snapshot {"hash":"2072e7428dbab6b430f4737003ce73d6bdcef4da","type":"PACKAGE_SPEC","name":"VL_PKG_CRUD_COMPANY","schemaName":"VERANOLINK","sxml":""}