-- liquibase formatted sql
-- changeset VERANOLINK:1785188144987 stripComments:false  logicalFilePath:base-release\veranolink\package_bodies\vl_pkg_restore.sql
-- sqlcl_snapshot db/src/database/veranolink/package_bodies/vl_pkg_restore.sql:null:3cfcedb8e282922b355d8d2a6a5c0ba20ecbbc06:create

create or replace package body veranolink.vl_pkg_restore is

    function vl_restore (
        p_email in varchar2
    ) return boolean as
        v_mail vl_users.email%type;
    begin
        begin
            select
                email
            into v_mail
            from
                vl_users
            where
                email = p_email;

        exception
            when no_data_found then
                return false;
        end;

        return true;
    end;

    procedure update_password (
        p_password varchar2,
        p_email    varchar2
    ) as
        pass vl_users.password%type;
    begin
        select
            standard_hash(p_password, 'SHA256')
        into pass
        from
            dual;

        update vl_users
        set
            password = pass
        where
            standard_hash(email, 'SHA256') = p_email;

    end;

end vl_pkg_restore;
/

