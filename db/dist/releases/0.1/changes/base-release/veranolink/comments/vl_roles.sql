-- liquibase formatted sql
-- changeset veranolink:1785188144374 stripComments:false  logicalFilePath:base-release\veranolink\comments\vl_roles.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/vl_roles.sql:null:2a0a23a57f39e575576d1b2234cb212e51a80e03:create

comment on column veranolink.vl_roles.name is
    'Nombre del rol';

comment on column veranolink.vl_roles.vl_id_rol is
    'ID con secuencia autoincremental';

