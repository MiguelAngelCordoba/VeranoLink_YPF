-- liquibase formatted sql
-- changeset VERANOLINK:1785188155551 stripComments:false  logicalFilePath:base-release\veranolink\package_specs\vl_pkg_restore.sql
-- sqlcl_snapshot db/src/database/veranolink/package_specs/vl_pkg_restore.sql:null:debf24befe944ecb5471b5d537149ea58256345c:create

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

