comment on column veranolink.log_opc_sequence.hierarchy_path_id is
    'Ruta jerarquica exacta que se envio a Ecosys en esta llamada. Es auditoria pura: el path vigente para futuras actualizaciones NO se lee de aqui, se deriva en VIEW_SEQUENCE_UPDATE combinando la estructura de TBL_WBS con los OBJECT_CODE ya sincronizados'
    ;

comment on column veranolink.log_opc_sequence.object_code is
    'Codigo del objeto tal como quedo sincronizado en Ecosys (wbsCode o activityCode). CLAVE: con RESULTADO=OK es la fuente para derivar el path vigente de Ecosys, que puede diferir del actual de OPC si hubo renombrados'
    ;

comment on column veranolink.log_opc_sequence.project_baseline_id is
    'Linea base vigente al momento del envio. Comparar este valor contra la LB vigente actual es el disparador B de la actualizacion (cambio de linea base)'
    ;

comment on column veranolink.log_opc_sequence.update_sincronizado is
    'updateDate de OPC correspondiente a la version del objeto que se sincronizo. Pivote del disparador A de la actualizacion';


-- sqlcl_snapshot {"hash":"95ed2a7be7f0f16987e9f8f68d00505b070d990c","type":"COMMENT","name":"log_opc_sequence","schemaName":"veranolink","sxml":""}