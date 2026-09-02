comment on table veranolink.tbl_wbs_baseline is
    'Jerarquia WBS perteneciente a cada linea base, ya reconstruida y lista para enviar a Sequence. Se construye tomando los WBS_ID hoja de TBL_ACTIVITY_BASELINE y expandiendo hacia atras todos sus ancestros mediante coincidencia de prefijo sobre WBS_PATH en TBL_WBS'
    ;

comment on column veranolink.tbl_wbs_baseline.es_hoja_actividad is
    'Y = el WBS contiene actividades directamente (vino como wbsId del endpoint de baseline). N = es un nivel intermedio reconstruido para que la hoja pueda existir en Ecosys'
    ;

comment on column veranolink.tbl_wbs_baseline.id_tbl_wbs is
    'ID_FILA de la version de TBL_WBS de la que se copiaron code, name y path. Congela los datos usados al momento del envio';

comment on column veranolink.tbl_wbs_baseline.nivel is
    'Profundidad del WBS en la jerarquia, contando el nivel proyecto como 1. La construccion siempre inicia en el nivel 2';

comment on column veranolink.tbl_wbs_baseline.project_baseline_id is
    'Linea base a la que pertenece esta jerarquia. Permite ver exactamente que WBS se enviaron con cada LB';

comment on column veranolink.tbl_wbs_baseline.wbs_path is
    'Ruta jerarquica completa copiada de TBL_WBS. El primer nivel (proyecto) se reemplaza por CONTRACT_NUMBER al construir el HierarchyPathID en la vista de envio'
    ;


-- sqlcl_snapshot {"hash":"d35a7c1b14b628ccc1bace5a22d81435bcceef11","type":"COMMENT","name":"tbl_wbs_baseline","schemaName":"veranolink","sxml":""}