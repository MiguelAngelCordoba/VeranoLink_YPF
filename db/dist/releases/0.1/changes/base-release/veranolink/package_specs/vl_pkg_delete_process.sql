-- liquibase formatted sql
-- changeset VERANOLINK:1785188155397 stripComments:false  logicalFilePath:base-release\veranolink\package_specs\vl_pkg_delete_process.sql
-- sqlcl_snapshot db/src/database/veranolink/package_specs/vl_pkg_delete_process.sql:null:4696208c47568d67aaa1a2896435629b6bc2ab87:create

create or replace package veranolink.vl_pkg_delete_process as
    function drop_user_table (
        v_id_table in veranolink.vl_saved_tables.vl_id_saved_table%type
    ) return number;

    procedure verify_tables_used_on_apis (
        v_id_apu_table in veranolink.vl_apu_tables.id_vl_apu_table%type,
        v_id_user      in veranolink.vl_apu_tables.id_user%type
    );

end vl_pkg_delete_process;
/

