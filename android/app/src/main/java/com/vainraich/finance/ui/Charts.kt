package com.vainraich.finance.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vainraich.core.*

/** Projected balance (solid) vs confirmed-only (dashed). Time runs left → right. Tap/drag to inspect a day. */
@Composable
fun ForecastChart(f: Forecast, modifier: Modifier = Modifier) {
    val brand = Palette.brand; val actual = Palette.actual; val zero = Palette.liability; val grid = Palette.separator
    var sel by remember(f) { mutableStateOf<Int?>(null) }
    val days = f.days
    Card(modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("יתרה חזויה", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            sel?.let { i -> days.getOrNull(i)?.let { d ->
                Column(horizontalAlignment = Alignment.End) {
                    Text(d.date.il, style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                    Amount(d.projected, MaterialTheme.typography.titleSmall, bySign = true)
                }
            } }
        }
        if (days.size < 2) { Text("אין מספיק נתונים לגרף", color = Palette.secondaryText); return@Card }
        val values = days.flatMap { listOf(it.projected.toDouble(), it.confirmedOnly.toDouble()) } + 0.0
        val minV = values.min(); val maxV = values.max().let { if (it == minV) it + 1 else it }
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
            Canvas(
                Modifier.fillMaxWidth().height(190.dp)
                    .semantics { contentDescription = "גרף יתרה חזויה. בסוף התקופה ${f.ending.ils()}" }
                    .pointerInput(f) {
                        detectTapGestures { o -> sel = ((o.x / size.width) * (days.size - 1)).toInt().coerceIn(0, days.lastIndex) }
                    }
                    .pointerInput(f) {
                        detectDragGestures { c, _ -> sel = ((c.position.x / size.width) * (days.size - 1)).toInt().coerceIn(0, days.lastIndex) }
                    }
            ) {
                val w = size.width; val h = size.height
                fun x(i: Int) = w * i / (days.size - 1).toFloat()
                fun y(v: Double) = (h - (v - minV) / (maxV - minV) * h).toFloat()
                for (k in 0..3) { val yy = h * k / 3f; drawLine(grid, Offset(0f, yy), Offset(w, yy), 1f) }
                drawLine(zero.copy(alpha = 0.5f), Offset(0f, y(0.0)), Offset(w, y(0.0)), 2f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f)))
                val p = Path(); val area = Path(); val c = Path()
                days.forEachIndexed { i, d ->
                    val px = x(i); val py = y(d.projected.toDouble()); val cy = y(d.confirmedOnly.toDouble())
                    if (i == 0) { p.moveTo(px, py); area.moveTo(px, h); area.lineTo(px, py); c.moveTo(px, cy) } else { p.lineTo(px, py); area.lineTo(px, py); c.lineTo(px, cy) }
                }
                area.lineTo(w, h); area.close()
                drawPath(area, Brush.verticalGradient(listOf(brand.copy(alpha = 0.25f), brand.copy(alpha = 0.02f))))
                drawPath(c, actual.copy(alpha = 0.7f), style = Stroke(3f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 8f))))
                drawPath(p, brand, style = Stroke(5f, cap = StrokeCap.Round, join = StrokeJoin.Round))
                sel?.let { i -> drawLine(grid, Offset(x(i), 0f), Offset(x(i), h), 2f); drawCircle(brand, 8f, Offset(x(i), y(days[i].projected.toDouble()))) }
            }
            Row(Modifier.fillMaxWidth()) {
                Text(days.first().date.il, style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText, modifier = Modifier.weight(1f))
                Text(days.last().date.il, style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Legend(brand, "כולל צפוי ומשוער")
            Legend(actual, "רק מאושר")
            Text("טווח: ${MoneyFormatter.compact(minV.toBigDecimal())}–${MoneyFormatter.compact(maxV.toBigDecimal())}", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
        }
    }
}

@Composable
fun Legend(color: Color, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.size(width = 14.dp, height = 3.dp).background(color))
        Text(text, style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
    }
}

/** Grouped bars: income vs expenses per month, with net line. Oldest month on the left. */
@Composable
fun MonthlyBars(months: List<MonthSummary>, modifier: Modifier = Modifier, showNet: Boolean = false) {
    val inc = Palette.actual; val exp = Palette.liability; val net = Palette.brand; val grid = Palette.separator
    val maxV = (months.flatMap { listOf(it.income.toDouble(), it.expenses.toDouble()) }.maxOrNull() ?: 0.0).coerceAtLeast(1.0)
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        Column(modifier) {
            Canvas(Modifier.fillMaxWidth().height(170.dp).semantics { contentDescription = "גרף הכנסות והוצאות לפי חודש" }) {
                val w = size.width; val h = size.height
                for (k in 0..3) { val yy = h * k / 3f; drawLine(grid, Offset(0f, yy), Offset(w, yy), 1f) }
                val slot = w / months.size
                val bw = slot * 0.28f
                val pts = mutableListOf<Offset>()
                months.forEachIndexed { i, m ->
                    val cx = slot * i + slot / 2
                    val hi = (m.income.toDouble() / maxV * h).toFloat(); val he = (m.expenses.toDouble() / maxV * h).toFloat()
                    drawRoundRect(inc, Offset(cx - bw - 2, h - hi), Size(bw, hi), CornerRadius(6f))
                    drawRoundRect(exp, Offset(cx + 2, h - he), Size(bw, he), CornerRadius(6f))
                    pts += Offset(cx, (h - (m.net.toDouble().coerceAtLeast(0.0) / maxV * h)).toFloat())
                }
                if (showNet && pts.size > 1) {
                    val p = Path().apply { moveTo(pts[0].x, pts[0].y); pts.drop(1).forEach { lineTo(it.x, it.y) } }
                    drawPath(p, net, style = Stroke(4f)); pts.forEach { drawCircle(net, 6f, it) }
                }
            }
            Row(Modifier.fillMaxWidth()) {
                months.forEach { Text(Labels.month(it.month), style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText, modifier = Modifier.weight(1f), maxLines = 1, fontSize = 10.sp) }
            }
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Legend(inc, "הכנסות"); Legend(exp, "הוצאות"); if (showNet) Legend(net, "נטו")
        Text("מקסימום ${MoneyFormatter.compact(maxV.toBigDecimal())}", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
    }
}

@Composable
fun Donut(slices: List<Slice>, selected: String?, onSelect: (String?) -> Unit) {
    val colors = slices.map { Palette.token(it.colorToken) }
    val total = slices.sumOfMoney { it.amount }
    Box(Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(190.dp).clickable { onSelect(null) }) {
            var start = -90f
            slices.forEachIndexed { i, s ->
                val sweep = (s.share * 360).toFloat()
                drawArc(colors[i].copy(alpha = if (selected == null || selected == s.id) 1f else 0.3f), start, (sweep - 1.5f).coerceAtLeast(0.5f), false, style = Stroke(48f))
                start += sweep
            }
        }
        val sel = slices.firstOrNull { it.id == selected }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(sel?.name ?: "סה״כ", style = MaterialTheme.typography.labelMedium, color = Palette.secondaryText)
            Amount(sel?.amount ?: total, MaterialTheme.typography.titleMedium)
        }
    }
}

@Composable
fun ShareBar(share: Double, color: Color) {
    Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(Palette.elevated)) {
        Box(Modifier.fillMaxWidth(share.toFloat().coerceIn(0.02f, 1f)).fillMaxHeight().clip(RoundedCornerShape(3.dp)).background(color))
    }
}
