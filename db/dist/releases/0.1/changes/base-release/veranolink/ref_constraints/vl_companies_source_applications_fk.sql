-- liquibase formatted sql
-- changeset VERANOLINK:1785188155710 stripComments:false  logicalFilePath:base-release\veranolink\ref_constraints\vl_companies_source_applications_fk.sql
-- sqlcl_snapshot db/src/database/veranolink/ref_constraints/vl_companies_source_applications_fk.sql:null:b93ce7fa9370bb35a1550f950dba0c05877e3b40:create

alter table veranolink.vl_companies_source_applications
    add constraint vl_companies_source_applications_fk
        foreign key ( id_vl_source_application )
            references veranolink.vl_source_applications ( id_vl_source_application )
                on delete cascade
        enable;

