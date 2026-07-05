package de.tedi.paperless.ui

import androidx.compose.runtime.Composable
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import de.tedi.paperless.ui.documents.DocumentDetailScreen
import de.tedi.paperless.ui.documents.DocumentListScreen
import de.tedi.paperless.ui.login.LoginScreen
import de.tedi.paperless.ui.metadata.MetadataScreen
import de.tedi.paperless.ui.search.AskArchiveScreen
import de.tedi.paperless.ui.upload.UploadScreen

@Composable
fun PaperlessNavHost() {
    val navController = rememberNavController()
    NavHost(navController = navController, startDestination = "login") {
        composable("login") {
            LoginScreen(onLoggedIn = { navController.navigate("documents") { popUpTo("login") { inclusive = true } } })
        }
        composable("documents") {
            DocumentListScreen(
                onDocumentClick = { id -> navController.navigate("documents/$id") },
                onAskArchiveClick = { navController.navigate("ask") }
            )
        }
        composable("ask") { AskArchiveScreen() }
        composable(
            "documents/{id}",
            arguments = listOf(navArgument("id") { type = NavType.IntType })
        ) { backStackEntry ->
            val id = backStackEntry.arguments?.getInt("id") ?: return@composable
            DocumentDetailScreen(documentId = id)
        }
        composable("upload") { UploadScreen() }
        composable("metadata") { MetadataScreen() }
    }
}
