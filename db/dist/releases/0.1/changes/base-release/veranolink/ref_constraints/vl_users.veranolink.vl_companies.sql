-- liquibase formatted sql
-- changeset VERANOLINK:1785188155833 stripComments:false  logicalFilePath:base-release\veranolink\ref_constraints\vl_users.veranolink.vl_companies.sql
-- sqlcl_snapshot db/src/database/veranolink/ref_constraints/vl_users.veranolink.vl_companies.sql:null:6b059d0c9d6e8a04ed7d7331fac96332b5b58776:create

alter table veranolink.vl_users
    add
        foreign key ( vl_id_company )
            references veranolink.vl_companies ( vl_id_company )
        enable;

