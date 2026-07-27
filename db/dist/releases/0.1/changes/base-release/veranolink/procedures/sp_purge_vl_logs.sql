-- liquibase formatted sql
-- changeset VERANOLINK:1785188155659 stripComments:false  logicalFilePath:base-release\veranolink\procedures\sp_purge_vl_logs.sql
-- sqlcl_snapshot db/src/database/veranolink/procedures/sp_purge_vl_logs.sql:null:b0b2936d98c41f19c8ad83e7b16a8367f8e7d124:create

create or replace procedure veranolink.sp_purge_vl_logs as
begin
    for n in (
        select
            partition_name,
            high_value,
            partition_position
        from
            user_tab_partitions utp
        where
            utp.partition_position < (
                select
                    max(partition_position) - 6
                from
                    user_tab_partitions
                where
                    table_name = 'VL_LOGS'
            )
    ) loop
        execute immediate 'ALTER TABLE VL_LOGS TRUNCATE PARTITION ' || n.partition_name;
        commit;
        execute immediate 'ALTER TABLE VL_LOGS DROP PARTITION ' || n.partition_name;
        commit;
    end loop;
exception
    when others then
        dbms_output.put_line('Error inesperado : Mensaje'
                             || sqlcode
                             || sqlerrm
                             || ' Programa: '
                             || $$plsql_unit
                             || ' L�nea '
                             || $$plsql_line
                             || ' Backtrace: ' || dbms_utility.format_error_backtrace);
end sp_purge_vl_logs;
/

