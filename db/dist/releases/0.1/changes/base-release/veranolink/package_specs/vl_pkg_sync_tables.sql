-- liquibase formatted sql
-- changeset VERANOLINK:1785188155530 stripComments:false  logicalFilePath:base-release\veranolink\package_specs\vl_pkg_sync_tables.sql
-- sqlcl_snapshot db/src/database/veranolink/package_specs/vl_pkg_sync_tables.sql:null:eb4c53544825bc479c6d301ac247b08f450ddbc5:create

create or replace package veranolink.vl_pkg_sync_tables as
    procedure sp_create_table_job (
        job_name in varchar2
    );

    procedure sp_sync_table (
        iv_table_name in varchar2,
        iv_user_id    in number,
        iv_company    in varchar2
    );

    function create_job_for_sync_tables (
        v_job_name       in varchar2,
        v_new_state      in varchar2,
        v_new_interval   in varchar2,
        v_job_interval   in number,
        v_job_comments   in varchar2,
        get_id_table     in number,
        get_company      in number,
        get_company_name in varchar2
    ) return number;

end vl_pkg_sync_tables;
/

