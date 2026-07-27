-- liquibase formatted sql
-- changeset VERANOLINK:1785188155737 stripComments:false  logicalFilePath:base-release\veranolink\ref_constraints\fk_vl_saved_tables_application.sql
-- sqlcl_snapshot db/src/database/veranolink/ref_constraints/fk_vl_saved_tables_application.sql:null:c383cd9b52fb82e3021c9f1b86333b0d082651b1:create

alter table veranolink.vl_saved_tables
    add constraint fk_vl_saved_tables_application
        foreign key ( application )
            references veranolink.vl_source_applications ( id_vl_source_application )
        enable;

