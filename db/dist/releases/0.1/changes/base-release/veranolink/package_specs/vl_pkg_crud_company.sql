-- liquibase formatted sql
-- changeset VERANOLINK:1785188155448 stripComments:false  logicalFilePath:base-release\veranolink\package_specs\vl_pkg_crud_company.sql
-- sqlcl_snapshot db/src/database/veranolink/package_specs/vl_pkg_crud_company.sql:null:2072e7428dbab6b430f4737003ce73d6bdcef4da:create

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

