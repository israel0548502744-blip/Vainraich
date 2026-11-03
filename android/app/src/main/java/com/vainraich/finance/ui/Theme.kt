package com.vainraich.finance.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.sp
import com.vainraich.core.*

/** Design tokens with light and dark variants. */
object Palette {
    @Composable @ReadOnlyComposable private fun c(light: Long, dark: Long) = Color(if (isSystemInDarkTheme()) dark else light)

    val brand @Composable get() = c(0xFF0F7675, 0xFF2DD4BF)
    val brandSoft @Composable get() = c(0xFFE6F4F2, 0xFF0E2E2C)
    val actual @Composable get() = c(0xFF15803D, 0xFF4ADE80)
    val expected @Composable get() = c(0xFFB45309, 0xFFFBBF24)
    val receivable @Composable get() = c(0xFF6D28D9, 0xFFA78BFA)
    val liability @Composable get() = c(0xFFB91C1C, 0xFFF87171)
    val neutral @Composable get() = c(0xFF475569, 0xFF94A3B8)
    val background @Composable get() = c(0xFFF2F2F7, 0xFF000000)
    val card @Composable get() = c(0xFFFFFFFF, 0xFF1C1C1E)
    val elevated @Composable get() = c(0xFFF2F2F7, 0xFF2C2C2E)
    val secondaryText @Composable get() = c(0xFF6B7280, 0xFF9CA3AF)
    val separator @Composable get() = c(0x1F000000, 0x33FFFFFF)

    @Composable fun token(name: String): Color = when (name) {
        "green" -> c(0xFF16A34A, 0xFF4ADE80); "orange" -> c(0xFFEA580C, 0xFFFB923C); "blue" -> c(0xFF2563EB, 0xFF60A5FA)
        "indigo" -> c(0xFF4F46E5, 0xFF818CF8); "yellow" -> c(0xFFCA8A04, 0xFFFACC15); "teal" -> c(0xFF0D9488, 0xFF2DD4BF)
        "red" -> c(0xFFDC2626, 0xFFF87171); "pink" -> c(0xFFDB2777, 0xFFF472B6); "purple" -> c(0xFF7C3AED, 0xFFA78BFA)
        "mint" -> c(0xFF059669, 0xFF34D399); "brown" -> c(0xFF92400E, 0xFFD6A26A); else -> c(0xFF64748B, 0xFF94A3B8)
    }

    @Composable fun confidence(c: Confidence) = when (c) { Confidence.CONFIRMED -> actual; Confidence.EXPECTED -> expected; Confidence.ESTIMATED -> receivable }
    @Composable fun eventStatus(s: EventPaymentStatus) = when (s) {
        EventPaymentStatus.NONE -> neutral; EventPaymentStatus.UNPAID -> expected; EventPaymentStatus.PARTIALLY_PAID -> token("blue"); EventPaymentStatus.PAID -> actual
    }
    @Composable fun debtStatus(s: DebtStatus) = when (s) {
        DebtStatus.OPEN -> expected; DebtStatus.PARTIALLY_PAID -> token("blue"); DebtStatus.PAID -> actual; else -> neutral
    }
    @Composable fun accountType(t: AccountType) = when (t) {
        AccountType.BANK -> token("blue"); AccountType.CASH -> token("green"); AccountType.BIT -> token("teal")
        AccountType.CREDIT_CARD -> liability; AccountType.SAVINGS -> token("indigo"); AccountType.OTHER -> neutral
    }
}

object Icon {
    fun of(token: String): ImageVector = when (token) {
        "cart" -> Icons.Outlined.ShoppingCart; "restaurant" -> Icons.Outlined.Restaurant; "car" -> Icons.Outlined.DirectionsCar
        "home" -> Icons.Outlined.Home; "bolt" -> Icons.Outlined.Bolt; "wifi" -> Icons.Outlined.Wifi; "health" -> Icons.Outlined.LocalHospital
        "bag" -> Icons.Outlined.ShoppingBag; "school" -> Icons.Outlined.School; "star" -> Icons.Outlined.Star; "camera" -> Icons.Outlined.PhotoCamera
        "percent" -> Icons.Outlined.Percent; "work" -> Icons.Outlined.Work; "undo" -> Icons.Outlined.Undo; "gift" -> Icons.Outlined.CardGiftcard
        "bank" -> Icons.Outlined.AccountBalance; "person" -> Icons.Outlined.Person; "tag" -> Icons.Outlined.Sell
        else -> Icons.Outlined.MoreHoriz
    }
    fun account(t: AccountType): ImageVector = when (t) {
        AccountType.BANK -> Icons.Outlined.AccountBalance; AccountType.CASH -> Icons.Outlined.Payments; AccountType.BIT -> Icons.Outlined.PhoneAndroid
        AccountType.CREDIT_CARD -> Icons.Outlined.CreditCard; AccountType.SAVINGS -> Icons.Outlined.Savings; AccountType.OTHER -> Icons.Outlined.AccountBalanceWallet
    }
    fun kind(k: TxKind): ImageVector = when (k) {
        TxKind.INCOME -> Icons.Outlined.SouthWest; TxKind.EXPENSE -> Icons.Outlined.NorthEast
        TxKind.TRANSFER -> Icons.Outlined.SwapHoriz; TxKind.ADJUSTMENT -> Icons.Outlined.Tune
    }
}

/** Numbers: rounded, tabular, always left-to-right. */
val AmountStyle = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.SemiBold, textDirection = TextDirection.Ltr, fontFeatureSettings = "tnum")

@Composable
fun VainraichTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val scheme = if (dark) darkColorScheme(
        primary = Color(0xFF2DD4BF), onPrimary = Color(0xFF00201E), secondary = Color(0xFF2DD4BF),
        background = Color.Black, surface = Color(0xFF1C1C1E), surfaceVariant = Color(0xFF2C2C2E), surfaceContainer = Color(0xFF1C1C1E),
        error = Color(0xFFF87171),
    ) else lightColorScheme(
        primary = Color(0xFF0F7675), onPrimary = Color.White, secondary = Color(0xFF0F7675),
        background = Color(0xFFF2F2F7), surface = Color.White, surfaceVariant = Color(0xFFF2F2F7), surfaceContainer = Color.White,
        error = Color(0xFFB91C1C),
    )
    val base = Typography()
    MaterialTheme(
        colorScheme = scheme,
        typography = base.copy(
            headlineLarge = base.headlineLarge.copy(fontWeight = FontWeight.Bold),
            titleLarge = base.titleLarge.copy(fontWeight = FontWeight.Bold, fontSize = 22.sp),
        ),
        content = content,
    )
}
