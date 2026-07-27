-- liquibase formatted sql
-- changeset veranolink:1785188144496 stripComments:false  logicalFilePath:base-release\veranolink\comments\vl_source_applications.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/vl_source_applications.sql:null:6a5c49a1e38db6b13d516e6a3a5139aab49b542a:create

comment on table veranolink.vl_source_applications is
    'Aplicaciones Fuente';

comment on column veranolink.vl_source_applications.alias is
    'Alias del aplicativo (OPU, OPC)';

comment on column veranolink.vl_source_applications.id_vl_source_application is
    'Campo con llave autoincremental';

comment on column veranolink.vl_source_applications.name is
    'Nombre de la aplicaci�n i.e (UNIFIER,P6';

