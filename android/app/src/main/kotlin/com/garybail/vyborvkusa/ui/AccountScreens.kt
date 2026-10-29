package com.garybail.vyborvkusa.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.garybail.vyborvkusa.AppModel
import com.garybail.vyborvkusa.core.WatchApi
import com.garybail.vyborvkusa.core.Watch
import java.math.BigDecimal
import kotlinx.coroutines.launch

/** Блок аккаунта в профиле: кто вошёл, подтверждение почты, выход. */
@Composable
fun AccountSection(model: AppModel, nav: Nav) {
    val ant = Ant.colors
    val account = model.account
    val scope = rememberCoroutineScope()
    var code by rememberSaveable { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }
    AntCard {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (account == null) {
                Text("Войдите, чтобы следить за ценами сборок и получать напоминания, когда корзина дешевеет.",
                     color = ant.textSecondary, fontSize = 14.sp)
                Button(onClick = { nav.auth() }, modifier = Modifier.fillMaxWidth().testTag("login")) {
                    Text("Войти или зарегистрироваться")
                }
            } else {
                Text(account.displayName, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = ant.text)
                account.email?.let { Text(it, color = ant.textSecondary) }
                if (!account.isEmailVerified) {
                    AntTag("Почта не подтверждена", ant.gold)
                    OutlinedTextField(code, { code = it.filter(Char::isDigit).take(6) }, label = { Text("Код из письма") },
                                      singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                      modifier = Modifier.fillMaxWidth())
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = {
                            scope.launch { message = runCatching { model.verifyEmail(code) }.exceptionOrNull()?.message }
                        }, enabled = code.length >= 4) { Text("Подтвердить") }
                        TextButton(onClick = {
                            scope.launch {
                                message = runCatching { model.resendCode() }.fold({ "Отправили новый код" }, { it.message })
                            }
                        }) { Text("Прислать снова") }
                    }
                }
                message?.let { Text(it, color = ant.textSecondary, fontSize = 13.sp) }
                TextButton(onClick = { model.logout() }) { Text("Выйти", color = ant.error) }
            }
        }
    }
}

/** Вход и регистрация по почте. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuthScreen(model: AppModel, nav: Nav) {
    val ant = Ant.colors
    val scope = rememberCoroutineScope()
    var mode by rememberSaveable { mutableStateOf(0) }  // 0 — вход, 1 — регистрация, 2 — восстановление
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var name by rememberSaveable { mutableStateOf("") }
    var code by rememberSaveable { mutableStateOf("") }
    var codeSent by rememberSaveable { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }

    LaunchedEffect(model.account) { if (model.account != null) nav.back() }
    LaunchedEffect(model.serverUrl) { model.loadOAuthProviders() }
    val context = androidx.compose.ui.platform.LocalContext.current

    fun run(action: suspend () -> Unit) {
        busy = true
        error = null
        scope.launch {
            error = runCatching { action() }.exceptionOrNull()?.message
            busy = false
        }
    }

    ScreenScaffold(if (mode == 2) "Новый пароль" else "Аккаунт", onBack = { nav.back() }) { padding ->
        Column(Modifier.padding(padding).padding(16.dp).verticalScroll(rememberScrollState()),
               verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (model.serverUrl == null) {
                AntTag("Сначала укажите адрес сервера в профиле", ant.gold)
            }
            if (mode < 2) {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    listOf("Вход", "Регистрация").forEachIndexed { i, title ->
                        SegmentedButton(selected = mode == i, onClick = { mode = i; error = null },
                                        shape = SegmentedButtonDefaults.itemShape(i, 2)) { Text(title) }
                    }
                }
            }
            if (mode == 1) {
                OutlinedTextField(name, { name = it }, label = { Text("Имя") }, singleLine = true,
                                  modifier = Modifier.fillMaxWidth())
            }
            OutlinedTextField(email, { email = it }, label = { Text("Email") }, singleLine = true,
                              keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                              modifier = Modifier.fillMaxWidth().testTag("auth-email"))
            if (mode == 2 && codeSent) {
                OutlinedTextField(code, { code = it.filter(Char::isDigit).take(6) }, label = { Text("Код из письма") },
                                  singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                  modifier = Modifier.fillMaxWidth())
            }
            if (mode < 2 || codeSent) {
                OutlinedTextField(password, { password = it }, label = { Text(if (mode == 2) "Новый пароль" else "Пароль") },
                                  singleLine = true, visualTransformation = PasswordVisualTransformation(),
                                  keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                                  modifier = Modifier.fillMaxWidth().testTag("auth-password"),
                                  supportingText = { if (mode != 0) Text("Не короче 8 символов") })
            }
            error?.let { Text(it, color = ant.error) }
            Button(
                onClick = {
                    when {
                        mode == 0 -> run { model.login(email, password) }
                        mode == 1 -> run { model.register(email, password, name) }
                        !codeSent -> run { model.forgotPassword(email); codeSent = true }
                        else -> run { model.resetPassword(email, code, password) }
                    }
                },
                enabled = !busy && email.contains("@"),
                modifier = Modifier.fillMaxWidth().testTag("auth-submit"),
            ) {
                if (busy) CircularProgressIndicator(Modifier.height(20.dp).width(20.dp), strokeWidth = 2.dp)
                else Text(when {
                    mode == 0 -> "Войти"
                    mode == 1 -> "Создать аккаунт"
                    !codeSent -> "Прислать код"
                    else -> "Сохранить пароль"
                })
            }
            if (mode == 1) {
                Text("После регистрации пришлём код подтверждения на почту.", fontSize = 13.sp, color = ant.textSecondary)
            }
            if (mode < 2 && model.oauthProviders.isNotEmpty()) {
                Text("или", color = ant.textTertiary, modifier = Modifier.align(Alignment.CenterHorizontally))
                for (p in listOf("vk", "yandex").filter { it in model.oauthProviders }) {
                    OutlinedButton(onClick = {
                        model.oauthError = null
                        scope.launch {
                            model.startOAuth(p)?.let { url ->
                                context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW,
                                                                             android.net.Uri.parse(url)))
                            }
                        }
                    }, modifier = Modifier.fillMaxWidth().testTag("oauth-$p")) {
                        Text(if (p == "vk") "Войти через VK ID" else "Войти с Яндекс ID")
                    }
                }
                model.oauthError?.let { Text(it, color = ant.error) }
            }
            if (mode == 0) TextButton(onClick = { mode = 2; error = null }) { Text("Забыли пароль?") }
            if (mode == 2) TextButton(onClick = { mode = 0; codeSent = false; error = null }) { Text("Вернуться ко входу") }
        }
    }
}

/** «Следить за ценой» на странице сборки. */
@Composable
fun PriceWatchCard(model: AppModel, nav: Nav, buildId: String, watched: Boolean) {
    val ant = Ant.colors
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var watch by remember { mutableStateOf<Watch?>(null) }
    LaunchedEffect(watched) { watch = if (watched) model.watch(buildId) else null }
    val city = model.data.settings.cityId

    AntCard {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (model.account == null) {
                Text("Следить за ценой", fontWeight = FontWeight.SemiBold, color = ant.text)
                Text("Сервер трижды в день проверяет корзину в магазинах и напоминает, когда она дешевеет.",
                     fontSize = 13.sp, color = ant.textSecondary)
                OutlinedButton(onClick = { nav.auth() }) { Text("Войти, чтобы следить") }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Следить за ценой", fontWeight = FontWeight.SemiBold, color = ant.text, modifier = Modifier.weight(1f))
                    Switch(watched, { on ->
                        busy = true
                        scope.launch {
                            error = model.setWatched(buildId, on)
                            busy = false
                        }
                    }, enabled = !busy)
                }
                val best = watch?.best
                if (watched && best != null) {
                    Text("Сейчас дешевле всего: ${rub(BigDecimal(best.total))} · ${WatchApi.storeName(best.storeId)}",
                         color = ant.text)
                    watch?.usualTotal?.let { Text("Обычно: ${rub(BigDecimal(it))}", fontSize = 13.sp, color = ant.textSecondary) }
                } else if (watched) {
                    Text("Цены появятся после ближайшей проверки (в 7:00, 12:00 и 18:00).", fontSize = 13.sp,
                         color = ant.textSecondary)
                }
                Text(if (city != WatchApi.SUPPORTED_CITY) "Пока цены проверяются только для Санкт-Петербурга."
                     else "Проверяем Ленту, Магнит, Ашан, ВкусВилл и Купер в Петербурге.",
                     fontSize = 12.sp, color = ant.textTertiary)
            }
            error?.let { Text(it, color = ant.error, fontSize = 13.sp) }
        }
    }
    Spacer(Modifier.height(0.dp))
}
