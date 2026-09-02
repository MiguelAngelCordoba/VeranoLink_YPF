comment on column veranolink.tbl_project.estado_integracion is
    'Semaforo de integracion. OK = procede a WBS/Actividad. DUPLICADO = otro PROJECT_ID tiene el mismo Contract Number, no procede. CONTRATO_CAMBIADO = el Contract Number cambio respecto a lo que ya estaba guardado, la fila NO se actualiza esta corrida y queda congelada hasta correccion manual en OPC.'
    ;

comment on column veranolink.tbl_project.workspace_code is
    'ID del espacio de trabajo OPC que contiene el proyecto. Requerido junto con PROJECT_CODE por el endpoint View Activities by Baseline'
    ;

comment on column veranolink.tbl_project.workspace_id is
    'ID interno del espacio de trabajo OPC que contiene el proyecto. Se valida contra TBL_WORKSPACES antes de insertar o actualizar el proyecto.'
    ;


-- sqlcl_snapshot {"hash":"29abab55fcb167eea6435cf976a9191736628b27","type":"COMMENT","name":"tbl_project","schemaName":"veranolink","sxml":""}