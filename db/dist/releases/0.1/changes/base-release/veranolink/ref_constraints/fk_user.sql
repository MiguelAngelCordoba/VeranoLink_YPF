-- liquibase formatted sql
-- changeset VERANOLINK:1785188155625 stripComments:false  logicalFilePath:base-release\veranolink\ref_constraints\fk_user.sql
-- sqlcl_snapshot db/src/database/veranolink/ref_constraints/fk_user.sql:null:72ad65aa9d12b36b89820bbd21a6e27b9610cd4c:create

alter table veranolink.vl_tables_used_on_apus
    add constraint fk_user
        foreign key ( apu_id )
            references veranolink.vl_apu_tables ( id_vl_apu_table )
        enable;

