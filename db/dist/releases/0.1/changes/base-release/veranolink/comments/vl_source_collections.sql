-- liquibase formatted sql
-- changeset veranolink:1785188144478 stripComments:false  logicalFilePath:base-release\veranolink\comments\vl_source_collections.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/vl_source_collections.sql:null:6d145f1d5f3b5f51d2a49a746ab5fef3ee1a05d3:create

comment on table veranolink.vl_source_collections is
    'Tabla de coleciones';

comment on column veranolink.vl_source_collections.id_parent_collection is
    'ID Padre Colecci�n';

comment on column veranolink.vl_source_collections.id_vl_source_collection is
    'Llave autoincremental';

comment on column veranolink.vl_source_collections.name_collection is
    'Nombre de la hoja';

