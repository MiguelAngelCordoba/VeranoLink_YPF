-- liquibase formatted sql
-- changeset VERANOLINK:1787600191934 stripComments:false  logicalFilePath:feature\ajuste1_creacion2\veranolink\indexes\idx_log_object.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/idx_log_object.sql:null:ecb197550979abe65fa0a10f27d274ad1009fa08:create

create index veranolink.idx_log_object on
    veranolink.log_opc_sequence (
        tipo_objeto,
        object_id,
        resultado
    );

