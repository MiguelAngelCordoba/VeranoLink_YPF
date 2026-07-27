-- liquibase formatted sql
-- changeset veranolink:1785188144439 stripComments:false  logicalFilePath:base-release\veranolink\comments\vl_types_environment.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/vl_types_environment.sql:null:4b45fdd9d093bd0368d7e7b64c4e95d4457f1d13:create

comment on table veranolink.vl_types_environment is
    'Tipos de ambiente';

comment on column veranolink.vl_types_environment.type_environment is
    'Tipo de Ambiente';

