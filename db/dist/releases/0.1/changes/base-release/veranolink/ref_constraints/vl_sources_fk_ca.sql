-- liquibase formatted sql
-- changeset VERANOLINK:1785188155757 stripComments:false  logicalFilePath:base-release\veranolink\ref_constraints\vl_sources_fk_ca.sql
-- sqlcl_snapshot db/src/database/veranolink/ref_constraints/vl_sources_fk_ca.sql:null:cf1add700c76365165e00b8c8086f7f202fbd82f:create

alter table veranolink.vl_sources
    add constraint vl_sources_fk_ca
        foreign key ( id_vl_company_application )
            references veranolink.vl_companies_source_applications ( id_vl_company_application )
        enable;

