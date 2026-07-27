-- liquibase formatted sql
-- changeset VERANOLINK:1785188155776 stripComments:false  logicalFilePath:base-release\veranolink\ref_constraints\vl_source_assigns_fk_user.sql
-- sqlcl_snapshot db/src/database/veranolink/ref_constraints/vl_source_assigns_fk_user.sql:null:541f2ebaee065c1c2e03928b14fced78675e6ec3:create

alter table veranolink.vl_source_assigns
    add constraint vl_source_assigns_fk_user
        foreign key ( id_vl_user )
            references veranolink.vl_users ( vl_id_user )
        enable;

