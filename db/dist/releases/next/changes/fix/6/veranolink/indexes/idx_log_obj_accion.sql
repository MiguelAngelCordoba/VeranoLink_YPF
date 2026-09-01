-- liquibase formatted sql
-- changeset VERANOLINK:1788300191286 stripComments:false  logicalFilePath:fix\6\veranolink\indexes\idx_log_obj_accion.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/idx_log_obj_accion.sql:null:a80e2a2d856dddc76cd0d9d8fb8253de8bd35dd4:create

create index veranolink.idx_log_obj_accion on
    veranolink.log_opc_sequence (
        tipo_objeto,
        object_id,
        resultado,
        id_log
    );

