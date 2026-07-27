-- liquibase formatted sql
-- changeset veranolink:1785188144425 stripComments:false  logicalFilePath:base-release\veranolink\comments\vl_countries.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/vl_countries.sql:null:d974891d84d622c673451ce1fc040141fba6cd83:create

comment on column veranolink.vl_countries.name is
    'Nombre del pa�s';

comment on column veranolink.vl_countries.vl_id_country is
    'ID con secuencia autoincremental';

