-- liquibase formatted sql
-- changeset veranolink:1785188144400 stripComments:false  logicalFilePath:base-release\veranolink\comments\vl_companies.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/vl_companies.sql:null:4e4f21e238099d6c24ea50c6ab2f05b71246e3b9:create

comment on column veranolink.vl_companies.created_date is
    'Campo de fecha de creaci�n';

comment on column veranolink.vl_companies.name is
    'Nombre de la compa�ia';

comment on column veranolink.vl_companies.short_name is
    'Nombre corto de la compa�ia';

comment on column veranolink.vl_companies.vl_id_company is
    'ID CON SECUENCIA AUTOINCREMENTAL';

comment on column veranolink.vl_companies.vl_id_country is
    'Llave foranea que indica el pa�s de la compa�ia';

