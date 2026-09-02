-- liquibase formatted sql
-- changeset VERANOLINK:1788300191281 stripComments:false  logicalFilePath:fix\6\veranolink\indexes\idx_log_object.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/idx_log_object.sql:null:ecb197550979abe65fa0a10f27d274ad1009fa08:create

create index veranolink.idx_log_object on
    veranolink.log_opc_sequence (
        tipo_objeto,
        object_id,
        resultado
    );

