comment on table veranolink.vl_sources is
    'Tabla que almacena las fuentes de consumo de servicios web';

comment on column veranolink.vl_sources.created_date is
    'Fecha de creaci�n del registro';

comment on column veranolink.vl_sources.id_vl_company_application is
    'Llave For�nea con los tipos de fuente';

comment on column veranolink.vl_sources.id_vl_source is
    'Campo Autoincrementa';

comment on column veranolink.vl_sources.id_vl_ws_type is
    'Llave for�nea al tipo de servicio web';

comment on column veranolink.vl_sources.source_authentication is
    'Autenticaci�n en base 64 y encriptada sha256(username:password)';

comment on column veranolink.vl_sources.source_url is
    'URL Fuente';


-- sqlcl_snapshot {"hash":"44afef2b18b835b72be4234501258e30babe281c","type":"COMMENT","name":"vl_sources","schemaName":"veranolink","sxml":""}