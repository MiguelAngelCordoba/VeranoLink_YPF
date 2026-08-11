create or replace package veranolink.pkg_envio_sequence as

    -- Envía a Sequence todos los objetos pendientes de creación (VIEW_SEQUENCE_CREATE),
    -- agrupados por proyecto: primero WBS del proyecto, luego Actividades del proyecto.
    -- Cada objeto enviado genera una fila en LOG_OPC_SEQUENCE con el resultado.
    procedure enviar_creacion;

    procedure integracion_diaria;

end pkg_envio_sequence;
/


-- sqlcl_snapshot {"hash":"75dda65b7cfe3184ca086ea9fae8a92a5343bdb8","type":"PACKAGE_SPEC","name":"PKG_ENVIO_SEQUENCE","schemaName":"VERANOLINK","sxml":""}