-- liquibase formatted sql
-- changeset veranolink:1785188144418 stripComments:false  logicalFilePath:base-release\veranolink\comments\vl_call_types.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/vl_call_types.sql:null:4e731471fde4a5d5538b194ce0be7810f889e67f:create

comment on table veranolink.vl_call_types is
    'Tipos de llamada a los servicios web';

comment on column veranolink.vl_call_types.call_name is
    'Nombre de la llamada';

comment on column veranolink.vl_call_types.created_date is
    'Campo fecha creaci�n de registro';

comment on column veranolink.vl_call_types.id_vl_call_type is
    'Llave autonincremental';

