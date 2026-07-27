-- liquibase formatted sql
-- changeset VERANOLINK:1785188155821 stripComments:false  logicalFilePath:base-release\veranolink\ref_constraints\vl_users.veranolink.vl_roles.sql
-- sqlcl_snapshot db/src/database/veranolink/ref_constraints/vl_users.veranolink.vl_roles.sql:null:3b5994d46d78b6b277fe1e4197f650f2a94ce16a:create

alter table veranolink.vl_users
    add
        foreign key ( vl_id_rol )
            references veranolink.vl_roles ( vl_id_rol )
        enable;

