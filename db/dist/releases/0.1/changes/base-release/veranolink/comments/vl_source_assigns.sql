-- liquibase formatted sql
-- changeset veranolink:1785188144487 stripComments:false  logicalFilePath:base-release\veranolink\comments\vl_source_assigns.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/vl_source_assigns.sql:null:542b61bf9518e1bb9ce41f1f326fdaacdcb60355:create

comment on table veranolink.vl_source_assigns is
    'Relaci�n de Fuentes con contextos por empresa';

comment on column veranolink.vl_source_assigns.id_vl_source_environment is
    'Referencia a Contextos';

comment on column veranolink.vl_source_assigns.id_vl_user is
    'Referencia a Fuentes';

