-- liquibase formatted sql
-- changeset VERANOLINK:1785188155700 stripComments:false  logicalFilePath:base-release\veranolink\ref_constraints\vl_companies_source_applications_fk_cp.sql
-- sqlcl_snapshot db/src/database/veranolink/ref_constraints/vl_companies_source_applications_fk_cp.sql:null:9871f43dcfabc186e646199df49eee0c8cd199f3:create

alter table veranolink.vl_companies_source_applications
    add constraint vl_companies_source_applications_fk_cp
        foreign key ( vl_id_company )
            references veranolink.vl_companies ( vl_id_company )
                on delete cascade
        enable;

