begin
    dbms_scheduler.create_job(
        job_name            => 'VERANOLINK.JOB_INTEGRACION_DIARIA',
        job_type            => 'PLSQL_BLOCK',
        job_action          => 'BEGIN PKG_ENVIO_SEQUENCE.INTEGRACION_DIARIA; END;',
        start_date          => timestamp '2026-08-01 22:00:00.0',
        repeat_interval     => 'FREQ=DAILY; BYHOUR=22; BYMINUTE=0; BYSECOND=0',
        end_date            => null,
        job_class           => 'DEFAULT_JOB_CLASS',
        comments            => 'Integracion nocturna OPC -> Sequence: proyectos, WBS, actividades, envio de creaciones',
        auto_drop           => true,
        number_of_arguments => 0
    );

    dbms_scheduler.set_attribute(
        name      => 'VERANOLINK.JOB_INTEGRACION_DIARIA',
        attribute => 'logging_level',
        value     => dbms_scheduler.logging_off
    );

    dbms_scheduler.set_attribute(
        name      => 'VERANOLINK.JOB_INTEGRACION_DIARIA',
        attribute => 'job_priority',
        value     => 3
    );

    dbms_scheduler.enable('VERANOLINK.JOB_INTEGRACION_DIARIA');
end;
/


-- sqlcl_snapshot {"hash":"278cd6205f88c2e6082bc31ebfc0de7fe6733ebd","type":"JOB","name":"JOB_INTEGRACION_DIARIA","schemaName":"VERANOLINK","sxml":""}