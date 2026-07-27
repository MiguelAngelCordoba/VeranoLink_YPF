-- liquibase formatted sql
-- changeset VERANOLINK:1785188155724 stripComments:false  logicalFilePath:base-release\veranolink\ref_constraints\vl_companies.veranolink.vl_countries.sql
-- sqlcl_snapshot db/src/database/veranolink/ref_constraints/vl_companies.veranolink.vl_countries.sql:null:6d01817f5d75d0edd4b11ef3d1e05e525478e7e7:create

alter table veranolink.vl_companies
    add
        foreign key ( vl_id_country )
            references veranolink.vl_countries ( vl_id_country )
        enable;

