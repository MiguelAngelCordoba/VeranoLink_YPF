create or replace package body veranolink.vl_pkg_delete_process as

    function drop_user_table (

        --ID de donde se obtendra lo datos relevantes de los objetos a eliminar
        v_id_table in veranolink.vl_saved_tables.vl_id_saved_table%type
    ) return number is

        --Variables internas
        v_view_name veranolink.vl_saved_tables.view_name%type;
        v_job_name  user_scheduler_jobs.job_name%type;
    begin

        --Obtenermos los datos necesarios para hacer el borrado en cascada , la vista para los json documents y el job name para el job

        select
            view_name,
            job_name
        into
            v_view_name,
            v_job_name
        from
            vl_saved_tables vl_st
        where
            vl_st.vl_id_saved_table = v_id_table;

        return 1;
    exception
        when no_data_found then
            return 2; --Si no se encuentra los valores a eliminar
    end drop_user_table;

    -- Fucion usada en TRG_AFTER_INSERT_NEW_REPORT_ANALYSIS

    procedure verify_tables_used_on_apis (
        v_id_apu_table in veranolink.vl_apu_tables.id_vl_apu_table%type,
        v_id_user      in veranolink.vl_apu_tables.id_user%type
    ) as

        v_query_id       varchar2(30);
        v_source         user_ords_handlers.source%type;

        -- Cursor para obtener los objetos utilizados en la consulta segun el id asignado
        cursor cur_objects_used_query is
        select distinct
            object_name
        from
            plan_table
        where
            object_type in ( 'TABLE', 'VIEW', 'INDEX', 'MATERIALIZED VIEW', 'SEQUENCE',
                             'PROCEDURE', 'FUNCTION', 'PACKAGE', 'TRIGGER', 'SYNONYM',
                             'TYPE', 'CLUSTER', 'QUEUE', 'DIRECTORY' )
            and object_name is not null
            and statement_id = v_query_id;

        -- Cursor para obtener las tablas creadas por el usuario
        cursor cur_tables_used is
        select distinct
            vl_id_saved_table,
            table_name
        from
            vl_saved_tables
        where
            id_user = v_id_user;

        -- Variables para comparación
        v_object_name    plan_table.object_name%type;
        v_table_name     vl_saved_tables.table_name%type;
        v_id_saved_table vl_saved_tables.vl_id_saved_table%type;
    begin

        -- Generar ID único
        v_query_id := to_char(systimestamp, 'YYYYMMDD_HH24MISSFF3');
        dbms_output.put_line('📌 Usando V_QUERY_ID: ' || v_query_id);

        -- Obtener el source del API
        select
            ha.source
        into v_source
        from
                 vl_apu_tables vl
            join user_ords_templates te on instr(vl.api_endpoint, te.uri_template) > 0
            join user_ords_handlers  ha on te.id = ha.template_id
        where
                vl.id_vl_apu_table = v_id_apu_table
            and rownum = 1;

        -- Verificar si hay datos en el source antes de ejecutar EXPLAIN PLAN
        if v_source is not null then
            dbms_output.put_line('📌 Usando el query: ' || dbms_lob.substr(v_source, 4000, 1));

            execute immediate 'EXPLAIN PLAN SET STATEMENT_ID = '''
                              || v_query_id
                              || ''' FOR '
                              || dbms_lob.substr(v_source, 4000, 1);

            commit;       

            -- **Abrir y mostrar todos los valores recuperados en cur_objects_used_query**
            dbms_output.put_line('📋 LISTA DE OBJECT_NAME RECUPERADOS:');
            open cur_objects_used_query;
            loop
                fetch cur_objects_used_query into v_object_name;
                exit when cur_objects_used_query%notfound;

                -- Imprimir cada objeto recuperado antes de iniciar la comparación
                dbms_output.put_line('  - ' || v_object_name);
            end loop;

            close cur_objects_used_query;

            -- **Ahora procedemos con la comparación**
            dbms_output.put_line('🔎 INICIANDO COMPARACIÓN...');

            -- Abrimos los cursores nuevamente para el proceso de comparación
            open cur_objects_used_query;
            open cur_tables_used;
            loop
                fetch cur_objects_used_query into v_object_name;
                exit when cur_objects_used_query%notfound;

                -- **Imprimir el objeto que está siendo evaluado**
                dbms_output.put_line('🔍 Evaluando OBJECT_NAME: ' || v_object_name);

                -- Recorrer todas las tablas del usuario para compararlas con el objeto
                loop
                    fetch cur_tables_used into
                        v_id_saved_table,
                        v_table_name;
                    exit when cur_tables_used%notfound;

                    -- **Imprimir qué tabla del usuario se está comparando**
                    dbms_output.put_line('  🔄 Comparando con TABLE_NAME: '
                                         || v_table_name
                                         || ' (ID: '
                                         || v_id_saved_table || ')');

                    -- Comparar nombres de tablas (insensible a mayúsculas)
                    if upper(v_object_name) = upper(v_table_name) then
                        dbms_output.put_line('✅ COINCIDENCIA: '
                                             || v_object_name
                                             || ' = ' || v_table_name);
                        insert into vl_tables_used_on_apus (
                            apu_id,
                            saved_table_id
                        ) values
                            ( v_id_apu_table,
                              v_id_saved_table );

                    end if;

                end loop;

                -- 🔹 Volver a abrir `cur_tables_used` para la siguiente iteración de `cur_objects_used_query`
                close cur_tables_used;
                open cur_tables_used;
            end loop;

            -- Cerrar los cursores al final
            close cur_objects_used_query;
            close cur_tables_used;

            -- Mover el COMMIT fuera del bucle para confirmar todas las inserciones
            commit;
            dbms_output.put_line('✅ Inserción finalizada.');
        end if;

    exception
        when others then
            null;
    end verify_tables_used_on_apis;

end vl_pkg_delete_process;
/


-- sqlcl_snapshot {"hash":"701978ddb0ef52aff7961a73204ff3fec891c8b3","type":"PACKAGE_BODY","name":"VL_PKG_DELETE_PROCESS","schemaName":"VERANOLINK","sxml":""}