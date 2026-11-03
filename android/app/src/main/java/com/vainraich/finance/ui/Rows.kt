package com.vainraich.finance.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.vainraich.core.*
import com.vainraich.finance.AppViewModel

@Composable
fun TransactionRow(vm: AppViewModel, t: Transaction, showDate: Boolean = true, onClick: (() -> Unit)? = null) {
    val cat = vm.data.category(t.categoryId)
    val signed = when (t.kind) {
        TxKind.INCOME, TxKind.TRANSFER -> t.amount
        TxKind.EXPENSE -> t.amount.negate()
        TxKind.ADJUSTMENT -> if (t.adjustmentIsNegative) t.amount.negate() else t.amount
    }
    val color = when {
        t.status != TxStatus.COMPLETED -> Palette.expected
        t.kind == TxKind.INCOME -> Palette.actual
        t.kind == TxKind.EXPENSE -> MaterialTheme.colorScheme.onSurface
        else -> Palette.neutral
    }
    val icon = when (t.kind) { TxKind.TRANSFER, TxKind.ADJUSTMENT -> Icon.kind(t.kind); else -> cat?.let { Icon.of(it.icon) } ?: Icon.kind(t.kind) }
    val iconColor = if (t.kind == TxKind.TRANSFER || t.kind == TxKind.ADJUSTMENT) Palette.neutral else cat?.let { Palette.token(it.colorToken) } ?: Palette.neutral
    val parts = buildList {
        if (showDate) add(t.date.relative(vm.today))
        if (t.kind == TxKind.TRANSFER) add("${vm.data.account(t.accountId)?.name.orEmpty()} ← ${vm.data.account(t.counterAccountId)?.name.orEmpty()}")
        else { cat?.let { add(it.name) }; vm.data.account(t.accountId)?.let { add(it.name) } }
    }
    Row(
        Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        IconBubble(icon, iconColor)
        Column(Modifier.weight(1f)) {
            Text(t.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(parts.joinToString(" · "), style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (t.status == TxStatus.PENDING) Badge("ממתין", Palette.expected)
                if (t.status == TxStatus.CANCELLED) Badge("בוטל", Palette.neutral)
                if (t.eventId != null) Icon(Icons.Outlined.Event, null, tint = Palette.secondaryText, modifier = Modifier.size(14.dp))
                if (t.attachmentFile != null) Icon(Icons.Outlined.AttachFile, null, tint = Palette.secondaryText, modifier = Modifier.size(14.dp))
            }
        }
        val style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold, textDecoration = if (t.status == TxStatus.CANCELLED) TextDecoration.LineThrough else null)
        Amount(signed, style, color = color, plus = t.kind == TxKind.INCOME)
    }
}

@Composable
fun ForecastRow(vm: AppViewModel, item: ForecastItem) {
    val c = Palette.confidence(item.confidence)
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(9.dp).clip(CircleShape).background(c))
        Column(Modifier.weight(1f)) {
            Text(item.title, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(item.date.relative(vm.today), style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                Badge(Labels.confidence(item.confidence), c)
                if (item.isOverdue) Badge("באיחור", Palette.liability)
            }
        }
        Amount(item.amount, MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), bySign = true, plus = true)
    }
}

@Composable
fun EventRow(vm: AppViewModel, e: FinanceEvent, onClick: () -> Unit) {
    val status = Events.paymentStatus(e, vm.data, vm.today)
    val sc = Palette.eventStatus(status)
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.width(4.dp).height(40.dp).clip(RoundedCornerShape(2.dp)).background(sc))
        Column(Modifier.weight(1f)) {
            Text(e.title, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val sub = listOfNotNull(e.startTime?.let { s -> e.endTime?.let { "$s–$it" } ?: "$s" }, vm.data.contact(e.contactId)?.name, e.location.ifBlank { null })
            if (sub.isNotEmpty()) Text(sub.joinToString(" · "), style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText, maxLines = 1)
        }
        Column(horizontalAlignment = Alignment.End) {
            val inc = e.expectedIncome
            if (inc != null && inc.isPos) { Amount(inc, MaterialTheme.typography.bodyMedium, color = sc); Badge(Labels.eventPayment(status), sc) }
            else if (e.expectedExpense?.isPos == true) Amount(e.expectedExpense!!.negate(), MaterialTheme.typography.bodyMedium, color = Palette.liability)
            else if (status == EventPaymentStatus.PAID) Badge("שולם", Palette.actual)
        }
    }
}

@Composable
fun DebtRow(vm: AppViewModel, b: DebtBalance, onClick: () -> Unit) {
    val d = b.debt
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(vm.data.contact(d.contactId)?.name.orEmpty(), fontWeight = FontWeight.Medium)
                Text(d.title, style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
            }
            Column(horizontalAlignment = Alignment.End) {
                Amount(if (b.isOpen) b.remaining else d.originalAmount, MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold))
                when {
                    b.isOverdue -> Badge("באיחור", Palette.liability)
                    b.isOpen && d.dueDate != null -> Text("עד ${d.dueDate!!.il}", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                    else -> Badge(Labels.debtStatus(b.status), Palette.debtStatus(b.status))
                }
            }
        }
        if (b.paid.isPos && b.isOpen) {
            LinearProgressIndicator(progress = { b.progress }, modifier = Modifier.fillMaxWidth(), color = Palette.actual)
            Text("שולם ${b.paid.ils()} מתוך ${d.originalAmount.ils()}", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
        }
    }
}

@Composable
fun AccountRow(a: Account, balance: Money, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        IconBubble(Icon.account(a.type), Palette.accountType(a.type))
        Column(Modifier.weight(1f)) {
            Text(a.name)
            val sub = listOfNotNull(a.institution, a.billingDay?.takeIf { a.type == AccountType.CREDIT_CARD }?.let { "חיוב ב־$it לחודש" },
                "לא נספר בזמין".takeIf { !a.includeInAvailable && a.type != AccountType.CREDIT_CARD })
            if (sub.isNotEmpty()) Text(sub.joinToString(" · "), style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
        }
        Amount(balance, MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold), bySign = a.type == AccountType.CREDIT_CARD)
    }
}

@Composable
fun Divider() = HorizontalDivider(color = Palette.separator)

@Composable
fun Dot(c: Color) = Box(Modifier.size(5.dp).clip(CircleShape).background(c))
