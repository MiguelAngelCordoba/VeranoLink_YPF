comment on column veranolink.tbl_project.estado_integracion is
    'Semaforo de integracion. OK = procede a WBS/Actividad. DUPLICADO = otro PROJECT_ID tiene el mismo Contract Number, no procede. CONTRATO_CAMBIADO = el Contract Number cambio respecto a lo que ya estaba guardado, la fila NO se actualiza esta corrida y queda congelada hasta correccion manual en OPC.'
    ;


-- sqlcl_snapshot {"hash":"92d99fab6a6555182bb5d9ee2f3071a1eb486d90","type":"COMMENT","name":"tbl_project","schemaName":"veranolink","sxml":""}