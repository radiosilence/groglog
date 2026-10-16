package cc.blit.groglog.ui.health

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.fromHtml
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import cc.blit.groglog.ui.theme.GrogLogTheme

/**
 * The privacy policy, which Health Connect opens from its permission screens to say what the data is used for. It is
 * the website's page, packaged at build time, so the two cannot disagree and it reads without a connection.
 */
class PrivacyActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val html = assets.open("privacy.html").bufferedReader().use { it.readText() }
        setContent { GrogLogTheme { Privacy(PolicyBlock.parse(html), onBack = ::finish) } }
    }
}

/** A heading or a paragraph of the policy, with its inline markup. */
data class PolicyBlock(val heading: Boolean, val html: String) {
    companion object {
        private val block = Regex("""<(h1|h2|p)[^>]*>(.*?)</\1>""", RegexOption.DOT_MATCHES_ALL)

        /** The page's main section, without the link back to the website's home page. */
        fun parse(page: String): List<PolicyBlock> {
            val main = page.substringAfter("<main", "").substringBefore("</main>")
            return block.findAll(main).map { match ->
                PolicyBlock(heading = match.groupValues[1] != "p", html = match.groupValues[2].replace(Regex("""\s+"""), " ").trim())
            }.toList()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Privacy(blocks: List<PolicyBlock>, onBack: () -> Unit) {
    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    val links = TextLinkStyles(SpanStyle(color = MaterialTheme.colorScheme.primary, textDecoration = TextDecoration.Underline))
    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text(blocks.firstOrNull { it.heading }?.let { AnnotatedString.fromHtml(it.html).text } ?: "Privacy") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                },
                scrollBehavior = scroll,
            )
        },
    ) { padding ->
        LazyColumn(
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // The page's own title is the app bar's.
            items(blocks.drop(1)) { block ->
                val text = AnnotatedString.fromHtml(block.html, linkStyles = links)
                if (block.heading) {
                    Text(text, style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                } else {
                    Text(text, style = MaterialTheme.typography.bodyLarge)
                }
            }
        }
    }
}

@Preview
@Composable
private fun PrivacyPreview() {
    GrogLogTheme {
        Privacy(
            listOf(
                PolicyBlock(true, "Privacy"),
                PolicyBlock(false, "GrogLog does not collect any information about you."),
                PolicyBlock(true, "Health Connect (Android)"),
                PolicyBlock(false, "Read on your phone and never sent anywhere. See the <a href=\"https://support.google.com\">policy</a>."),
            ),
            onBack = {},
        )
    }
}
