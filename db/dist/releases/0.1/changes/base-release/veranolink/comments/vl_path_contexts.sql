-- liquibase formatted sql
-- changeset veranolink:1785188144388 stripComments:false  logicalFilePath:base-release\veranolink\comments\vl_path_contexts.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/vl_path_contexts.sql:null:b4225e9e0f47339bf01440e8c7f3bfb509407611:create

comment on table veranolink.vl_path_contexts is
    'Almacena las rutas y los tipos de contextos';

comment on column veranolink.vl_path_contexts.created_date is
    'Fecha de creaci�n';

comment on column veranolink.vl_path_contexts.id_vl_call_type is
    'Tipo de Llamado';

comment on column veranolink.vl_path_contexts.id_vl_path_context is
    'Llave autoincremental';

comment on column veranolink.vl_path_contexts.id_vl_source_collection is
    'Fuente de servicio';

comment on column veranolink.vl_path_contexts.name is
    'Nombre del Contexto';

comment on column veranolink.vl_path_contexts.path_context is
    'Ruta del Contexto';

comment on column veranolink.vl_path_contexts.path_description is
    'Descripci�n del llamado';

