-- liquibase formatted sql
-- changeset veranolink:1785188144409 stripComments:false  logicalFilePath:base-release\veranolink\comments\vl_companies_source_applications.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/vl_companies_source_applications.sql:null:cd6620d4959c4cdc77ae8fe54d3f26a8ae3ec748:create

comment on table veranolink.vl_companies_source_applications is
    'Relaci�n de Compa��as contra modulos';

comment on column veranolink.vl_companies_source_applications.id_vl_source_application is
    'Aplicaciones Fuente';

comment on column veranolink.vl_companies_source_applications.vl_id_company is
    'Compa�ia';

