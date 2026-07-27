-- liquibase formatted sql
-- changeset veranolink:1785188144434 stripComments:false  logicalFilePath:base-release\veranolink\comments\vl_json_documents.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/vl_json_documents.sql:null:b63c2463b086483fec46f3e8d2d2609589b34249:create

comment on table veranolink.vl_json_documents is
    'Tabla que almacena los documentos JSON';

comment on column veranolink.vl_json_documents.id_vl_json_document is
    'Columna de autoincremento';

comment on column veranolink.vl_json_documents.id_vl_path_context is
    'Apuntamiento del Objeto que se esta trayendo';

comment on column veranolink.vl_json_documents.json_file is
    'Archivo JSON';

comment on column veranolink.vl_json_documents.json_name is
    'Nombre del Documento JSON o nombre del servicio web';

