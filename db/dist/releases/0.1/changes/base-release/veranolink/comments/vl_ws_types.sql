-- liquibase formatted sql
-- changeset veranolink:1785188144731 stripComments:false  logicalFilePath:base-release\veranolink\comments\vl_ws_types.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/vl_ws_types.sql:null:13641e763a4c8c1d197e73d6bb82abb31f98b4c1:create

comment on table veranolink.vl_ws_types is
    'Tipos de Consumo a los servicios web';

comment on column veranolink.vl_ws_types.created_date is
    'Fecha de creaci�n del registro';

comment on column veranolink.vl_ws_types.id_vl_ws_type is
    'Campo de autoincremento';

comment on column veranolink.vl_ws_types.name_ws is
    'Nombre del tipo de tecnolog�a de WS';

