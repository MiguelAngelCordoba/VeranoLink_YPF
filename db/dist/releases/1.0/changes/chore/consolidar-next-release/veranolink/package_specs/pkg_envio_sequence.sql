-- liquibase formatted sql
-- changeset VERANOLINK:1788372754364 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\package_specs\pkg_envio_sequence.sql
-- sqlcl_snapshot db/src/database/veranolink/package_specs/pkg_envio_sequence.sql:null:c78ff5282d1baa159dfa1ea2aab580324f30e9a5:create

create or replace package veranolink.pkg_envio_sequence as

    -- Crea en Ecosys los objetos pendientes (VIEW_SEQUENCE_CREATE).
    -- Por proyecto envia DOS peticiones: primero WBS en orden jerarquico
    -- (el padre debe existir antes que el hijo), luego actividades.
    procedure enviar_creacion;

    -- Actualiza en Ecosys los objetos que cambiaron (VIEW_SEQUENCE_UPDATE).
    -- Por proyecto envia UNA SOLA peticion con WBS y actividades juntas:
    -- Ecosys resuelve todos los paths del array contra el estado previo al
    -- request, por lo que todos deben ir con el path anterior al cambio.
    procedure enviar_actualizacion;

    -- Orquestacion nocturna completa.
    procedure integracion_diaria;

    -- Purga los lotes de LOG_LOTE anteriores a p_dias.
    -- LOG_LOTE es solo auditoria: ninguna vista ni logica depende de ella.
    -- NO purgar LOG_OPC_SEQUENCE: es el ancla de sincronizacion y borrarla
    -- haria que las vistas reenviaran todo a Ecosys como si nunca se hubiera
    -- creado. Ademas es pequena (los CLOB viven en LOG_LOTE).
    procedure purgar_log_lote (
        p_dias in number default 60
    );

end pkg_envio_sequence;
/

