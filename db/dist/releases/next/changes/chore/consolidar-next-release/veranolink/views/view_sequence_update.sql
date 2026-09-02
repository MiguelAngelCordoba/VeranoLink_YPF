-- liquibase formatted sql
-- changeset VERANOLINK:1788372755749 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\views\view_sequence_update.sql
-- sqlcl_snapshot db/src/database/veranolink/views/view_sequence_update.sql:null:5630d2b8ab094934a79cbbf918868b8858156fda:create

create or replace force editionable view veranolink.view_sequence_update (
    project_id,
    contract_number,
    project_baseline_id,
    "HierarchyPathID",
    "CostObjectID",
    "CostObjectName",
    "ExternalID",
    "Hours",
    "StartDateOBCost",
    "EndDateOBCost",
    "StartDateCBCost",
    "EndDateCBCost",
    tipo_objeto,
    orden_jerarquico,
    path_opc_actual,
    updatedate_actual,
    motivo,
    payload_json
) as
    with
-- ================= LINEA BASE VIGENTE =================
-- Se expone BASELINE_TYPE porque el camino B (linea base) solo puede
-- dispararse con CURRENT, mientras que el path del camino A si admite
-- ORIGINAL como respaldo cuando el proyecto nunca consumio una CURRENT.
     bl_vigente as (
        select
            x.project_id,
            x.project_baseline_id,
            x.baseline_type
        from
            (
                select
                    b.project_id,
                    b.project_baseline_id,
                    b.baseline_type,
                    row_number()
                    over(partition by b.project_id
                         order by
                             case b.baseline_type
                                 when 'CURRENT' then
                                     1
                                 else
                                     2
                             end, b.baseline_time desc
                    ) as rn
                from
                    tbl_project_baseline b
                where
                        b.vigente = 'Y'
                    and ( b.baseline_type = 'CURRENT'
                          or not exists (
                        select
                            1
                        from
                            tbl_project_baseline c
                        where
                                c.project_id = b.project_id
                            and c.baseline_type = 'CURRENT'
                            and c.fecha_primer_consumo is not null
                    ) )
            ) x
        where
            x.rn = 1
    ),
-- ================= ESTADO SINCRONIZADO EN ECOSYS =================
-- Ultimo envio exitoso por objeto. Su OBJECT_CODE es el codigo que Ecosys
-- conoce hoy, que puede diferir del actual de OPC si hubo un renombrado
-- que aun no se sincroniza. Es la pieza clave para derivar el path vigente.
-- OJO: cada fila refleja SOLO los campos que viajaron en ese envio. Un update
-- parcial deja OBJECT_NAME nulo, por lo que este dato NO sirve para detectar
-- cambios de linea base.
     obj_sinc as (
        select
            z.tipo_objeto,
            z.object_id,
            z.object_code,
            z.object_name,
            z.update_sincronizado,
            z.project_baseline_id
        from
            (
                select
                    l.tipo_objeto,
                    l.object_id,
                    l.object_code,
                    l.object_name,
                    l.update_sincronizado,
                    l.project_baseline_id,
                    row_number()
                    over(partition by l.tipo_objeto, l.object_id
                         order by
                             l.id_log desc
                    ) as rn
                from
                    log_opc_sequence l
                where
                    l.resultado = 'OK'
            ) z
        where
            z.rn = 1
    ),
-- ================= ESTRUCTURA JERARQUICA =================
     wbs_ultimo as (
        select
            w.*,
            length(w.wbs_path) - length(replace(w.wbs_path, '.', '')) + 1 as nivel
        from
            tbl_wbs w
        where
            w.updatedate = (
                select
                    max(w2.updatedate)
                from
                    tbl_wbs w2
                where
                    w2.wbs_id = w.wbs_id
            )
    ),
-- Cadena de ancestros de cada WBS (incluyendose a si mismo), desde el nivel 2.
-- El nivel 1 es el proyecto y en Ecosys se reemplaza por el CONTRACT_NUMBER.
-- El punto en el LIKE evita falsos prefijos ('PROJ.A' no es ancestro de 'PROJ.AB').
     wbs_ancestros as (
        select
            h.wbs_id as wbs_id_hijo,
            h.project_id,
            a.wbs_id as wbs_id_anc,
            a.wbs_code,
            a.nivel
        from
                 wbs_ultimo h
            join wbs_ultimo a on a.project_id = h.project_id
                                 and ( h.wbs_path = a.wbs_path
                                       or h.wbs_path like a.wbs_path || '.%' )
        where
            a.nivel >= 2
    ),
-- ================= PATH VIGENTE EN ECOSYS (DERIVADO) =================
-- No se lee de ninguna columna: se arma recorriendo los ancestros y usando
-- el codigo YA SINCRONIZADO de cada eslabon (obj_sinc), no el codigo actual
-- de OPC. Si un ancestro nunca se sincronizo, se cae al codigo de OPC.
-- Esto resuelve automaticamente a los "descendientes silenciosos": cuando se
-- renombra un WBS padre, Ecosys propaga el path a todos sus hijos y aqui el
-- path derivado los refleja sin necesidad de tocarlos.
     wbs_path_ecosys as (
        select
            anc.wbs_id_hijo as wbs_id,
            anc.project_id,
            p.contract_number
            || '.'
            ||
            listagg(nvl(cs.object_code, anc.wbs_code),
                    '.') within group(
                order by
                    anc.nivel
                )
            as path_ecosys
        from
                 wbs_ancestros anc
            join tbl_project p on p.project_id = anc.project_id
            left join obj_sinc    cs on cs.tipo_objeto = 'WBS'
                                     and cs.object_id = anc.wbs_id_anc
        group by
            anc.wbs_id_hijo,
            anc.project_id,
            p.contract_number
    ),
-- ================= DATOS DE LA LB VIGENTE =================
     act_bl as (
        select
            z.*
        from
            (
                select
                    a.*,
                    row_number()
                    over(partition by a.project_baseline_id, a.activity_id
                         order by
                             a.fecha_carga desc, a.id_fila desc
                    ) as rn
                from
                    tbl_activity_baseline a
            ) z
        where
            z.rn = 1
    ),
-- Ultima version del cronograma actual (Hours y fechas CB).
-- Se desempata por ID_FILA cuando hay updateDate iguales.
     act_viva as (
        select
            z.*
        from
            (
                select
                    a.*,
                    row_number()
                    over(partition by a.activity_id
                         order by
                             a.updatedate desc, a.id_fila desc
                    ) as rn
                from
                    tbl_activity a
            ) z
        where
            z.rn = 1
    )
-- ===================================================================
-- WBS: solo se actualizan codigo y nombre, y solo cambian via linea base.
-- El disparo exige una NUEVA ASIGNACION de LB CURRENT: se compara la LB
-- vigente contra la LB con la que el objeto quedo sincronizado.
-- ===================================================================
    select
        wb.project_id,
        p.contract_number,
        wb.project_baseline_id,
        pe.path_ecosys           as "HierarchyPathID",
        case
            when wb.wbs_code != os.object_code then
                wb.wbs_code
            else
                os.object_code
        end                      as "CostObjectID",
        wb.wbs_name              as "CostObjectName",
        to_char(wb.wbs_id)       as "ExternalID",
        null                     as "Hours",
        null                     as "StartDateOBCost",
        null                     as "EndDateOBCost",
        null                     as "StartDateCBCost",
        null                     as "EndDateCBCost",
        'WBS'                    as tipo_objeto,
        wb.nivel                 as orden_jerarquico,
        p.contract_number
        || substr(wb.wbs_path,
                  instr(wb.wbs_path, '.')) as path_opc_actual,
        wb.updatedate            as updatedate_actual,
        'LINEA_BASE'             as motivo,
    -- ABSENT ON NULL omite las claves nulas. Es esencial: enviar un campo
    -- vacio BORRA el dato en Ecosys, mientras que omitirlo lo deja intacto.
        json_object(
                'HierarchyPathID' value pe.path_ecosys,
                        'CostObjectID' value
                    case
                        when wb.wbs_code != os.object_code then
                            wb.wbs_code
                        else
                            os.object_code
                    end,
                        'CostObjectName' value wb.wbs_name,
                        'ExternalID' value to_char(wb.wbs_id)
            absent on null)
        as payload_json
    from
             tbl_wbs_baseline wb
        join bl_vigente      bv on bv.project_id = wb.project_id
                              and bv.project_baseline_id = wb.project_baseline_id
        join tbl_project     p on p.project_id = wb.project_id
-- INNER JOIN: solo se actualiza lo que ya existe en Ecosys
        join obj_sinc        os on os.tipo_objeto = 'WBS'
                            and os.object_id = wb.wbs_id
        join wbs_path_ecosys pe on pe.wbs_id = wb.wbs_id
-- Disparador unico: nueva asignacion de LB CURRENT.
    where
            bv.baseline_type = 'CURRENT'
        and bv.project_baseline_id != os.project_baseline_id
    union all
-- ===================================================================
-- ACTIVIDADES: dos disparadores independientes que pueden coincidir.
--   A (cronograma): UPDATEDATE mayor al sincronizado -> Hours + fechas CB
--   B (linea base): NUEVA ASIGNACION de LB CURRENT   -> fechas OB, codigo y nombre
-- Si ambos se disparan, la actividad sale UNA sola vez con la union de campos.
--
-- El camino B NO compara valores campo a campo contra obj_sinc: ese dato
-- refleja solo lo que viajo en el ultimo envio (un update parcial deja
-- OBJECT_NAME nulo) y provocaba reenvios infinitos. Se compara la baseline.
-- La LB ORIGINAL nunca dispara el camino B; solo sirve para resolver el path.
-- ===================================================================
    select
        av.project_id,
        p.contract_number,
        bv.project_baseline_id,
        pe.path_ecosys
        || '.'
        || os.object_code       as "HierarchyPathID",
        case
            when ab.activity_code != os.object_code then
                ab.activity_code
            else
                os.object_code
        end                     as "CostObjectID",
        case
            when bv.baseline_type = 'CURRENT'
                 and bv.project_baseline_id != os.project_baseline_id then
                ab.activity_name
        end                     as "CostObjectName",
        to_char(av.activity_id) as "ExternalID",
        case
            when av.updatedate > os.update_sincronizado then
                to_char(av.at_completion_labor_units)
        end                     as "Hours",
        case
            when bv.baseline_type = 'CURRENT'
                 and bv.project_baseline_id != os.project_baseline_id then
                to_char(
                    nvl(ab.bl_start_date, ab.bl_finish_date),
                    'YYYY-MM-DD'
                )
        end                     as "StartDateOBCost",
        case
            when bv.baseline_type = 'CURRENT'
                 and bv.project_baseline_id != os.project_baseline_id then
                to_char(
                    nvl(ab.bl_finish_date, ab.bl_start_date),
                    'YYYY-MM-DD'
                )
        end                     as "EndDateOBCost",
        case
            when av.updatedate > os.update_sincronizado then
                to_char(
                    nvl(av.startdate, av.finishdate),
                    'YYYY-MM-DD'
                )
        end                     as "StartDateCBCost",
        case
            when av.updatedate > os.update_sincronizado then
                to_char(
                    nvl(av.finishdate, av.startdate),
                    'YYYY-MM-DD'
                )
        end                     as "EndDateCBCost",
        'ACTIVITY'              as tipo_objeto,
        9999                    as orden_jerarquico,
        p.contract_number
        || substr(wbb.wbs_path,
                  instr(wbb.wbs_path, '.'))
        || '.'
        || ab.activity_code     as path_opc_actual,
        av.updatedate           as updatedate_actual,
        case
            when av.updatedate > os.update_sincronizado
                 and bv.baseline_type = 'CURRENT'
                 and bv.project_baseline_id != os.project_baseline_id then
                'CRONOGRAMA+LB'
            when av.updatedate > os.update_sincronizado then
                'CRONOGRAMA'
            else
                'LINEA_BASE'
        end                     as motivo,
        json_object(
                'HierarchyPathID' value pe.path_ecosys
                                        || '.'
                                        || os.object_code,
                        'CostObjectID' value
                    case
                        when ab.activity_code != os.object_code then
                            ab.activity_code
                        else
                            os.object_code
                    end,
                        'CostObjectName' value
                    case
                        when bv.baseline_type = 'CURRENT'
                             and bv.project_baseline_id != os.project_baseline_id then
                            ab.activity_name
                    end,
                        'Hours' value
                    case
                        when av.updatedate > os.update_sincronizado then
                            to_char(av.at_completion_labor_units)
                    end,
                        'StartDateOBCost' value
                    case
                        when bv.baseline_type = 'CURRENT'
                             and bv.project_baseline_id != os.project_baseline_id then
                            to_char(
                                nvl(ab.bl_start_date, ab.bl_finish_date),
                                'YYYY-MM-DD'
                            )
                    end,
                        'EndDateOBCost' value
                    case
                        when bv.baseline_type = 'CURRENT'
                             and bv.project_baseline_id != os.project_baseline_id then
                            to_char(
                                nvl(ab.bl_finish_date, ab.bl_start_date),
                                'YYYY-MM-DD'
                            )
                    end,
                        'StartDateCBCost' value
                    case
                        when av.updatedate > os.update_sincronizado then
                            to_char(
                                nvl(av.startdate, av.finishdate),
                                'YYYY-MM-DD'
                            )
                    end,
                        'EndDateCBCost' value
                    case
                        when av.updatedate > os.update_sincronizado then
                            to_char(
                                nvl(av.finishdate, av.startdate),
                                'YYYY-MM-DD'
                            )
                    end,
                        'ExternalID' value to_char(av.activity_id)
            absent on null)
        as payload_json
    from
             act_viva av
        join tbl_project      p on p.project_id = av.project_id
        join bl_vigente       bv on bv.project_id = av.project_id
-- Datos de la LB vigente (lo que deberia quedar en Ecosys)
        join act_bl           ab on ab.project_baseline_id = bv.project_baseline_id
                          and ab.activity_id = av.activity_id
-- INNER JOIN: solo se actualiza lo que ya existe en Ecosys
        join obj_sinc         os on os.tipo_objeto = 'ACTIVITY'
                            and os.object_id = av.activity_id
-- Path del WBS padre segun el estado real de Ecosys
        join wbs_path_ecosys  pe on pe.wbs_id = ab.wbs_id
-- Path de OPC, solo para auditoria
        join tbl_wbs_baseline wbb on wbb.project_baseline_id = bv.project_baseline_id
                                     and wbb.wbs_id = ab.wbs_id
    where
    -- Disparador A: avance en el cronograma actual
        av.updatedate > os.update_sincronizado
    -- Disparador B: nueva asignacion de LB CURRENT
        or ( bv.baseline_type = 'CURRENT'
             and bv.project_baseline_id != os.project_baseline_id );

