-- liquibase formatted sql
-- changeset VERANOLINK:1788372754266 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\indexes\idx_log_seq_lote.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/idx_log_seq_lote.sql:null:f188fa6cef961bf8909c00bdec7b661d7f7f334d:create

create index veranolink.idx_log_seq_lote on
    veranolink.log_opc_sequence (
        id_lote
    );

