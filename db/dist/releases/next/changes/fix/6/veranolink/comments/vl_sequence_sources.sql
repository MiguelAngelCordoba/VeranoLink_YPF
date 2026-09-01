-- liquibase formatted sql
-- changeset veranolink:1788300191295 stripComments:false  logicalFilePath:fix\6\veranolink\comments\vl_sequence_sources.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/vl_sequence_sources.sql:null:dd46eac0c91b1748a43ee08a6ad2747e5e91f320:create

comment on table veranolink.vl_sequence_sources is
    'Credenciales y URL base de Sequence (Basic Auth) por company y ambiente';

comment on column veranolink.vl_sequence_sources.company is
    'Ej: YPF';

comment on column veranolink.vl_sequence_sources.environment is
    'Ej: 2 = Stage, 3 = Prod (mismo criterio que VL_TYPES_ENVIRONMENT)';

comment on column veranolink.vl_sequence_sources.source_authentication is
    'Base64 de username:password';

comment on column veranolink.vl_sequence_sources.source_url is
    'URL base sin endpoint';

