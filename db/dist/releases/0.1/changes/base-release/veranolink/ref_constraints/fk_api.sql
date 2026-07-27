-- liquibase formatted sql
-- changeset VERANOLINK:1785188155638 stripComments:false  logicalFilePath:base-release\veranolink\ref_constraints\fk_api.sql
-- sqlcl_snapshot db/src/database/veranolink/ref_constraints/fk_api.sql:null:60032def1a61c9ad40745e329b06f16171086dbc:create

alter table veranolink.vl_tables_used_on_apus
    add constraint fk_api
        foreign key ( saved_table_id )
            references veranolink.vl_saved_tables ( vl_id_saved_table )
        enable;

