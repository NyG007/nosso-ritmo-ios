# Configuração Apple e iCloud

## 1. Preparar a equipe e os identificadores

O modo local de demonstração pode ser compilado para simulador sem configurar CloudKit. Para CloudKit e TestFlight, use uma assinatura ativa do Apple Developer Program. Não compartilhe sua conta Apple com sua esposa: cada um usa a própria conta iCloud.

Em `Config/Project.xcconfig`, configure:

| Variável | Valor inicial | Ajuste |
| --- | --- | --- |
| `APP_BUNDLE_ID` | `com.nyg007.nossoritmo` | Identificador único registrado na sua equipe |
| `WIDGET_BUNDLE_ID` | `com.nyg007.nossoritmo.widget` | Mesmo prefixo do app, com sufixo `.widget` |
| `CLOUD_CONTAINER_ID` | `iCloud.com.nyg007.nossoritmo` | Container iCloud registrado e associado ao app |
| `APP_GROUP_ID` | `group.com.nyg007.nossoritmo` | App Group compartilhado entre app e widget |
| `DEVELOPMENT_TEAM` | vazio | Team ID da assinatura Apple Developer |

Esses identificadores são configurações públicas, não senhas. Não coloque certificados, arquivos `.p8`, `.p12`, tokens ou perfis de provisionamento no Git.

No Xcode, selecione a equipe nos dois targets. Confira **Signing & Capabilities**:

- **NossoRitmo:** iCloud com CloudKit e o container; App Groups com o grupo; Push Notifications; Background Modes com Remote notifications.
- **NossoRitmoWidget:** App Groups com exatamente o mesmo grupo. A extensão não precisa acessar CloudKit diretamente.

Os entitlements e Info.plists já referenciam as variáveis compartilhadas. `CKSharingSupported` e o esquema `nossoritmo://` estão configurados. Debug usa `aps-environment=development`; Release usa `production`. A assinatura de distribuição deve resolver o ambiente iCloud de produção.

## 2. Primeira execução com CloudKit

1. Nos dois iPhones, entre em contas iCloud diferentes e habilite iCloud Drive.
2. Compile o app para um dispositivo físico com assinatura válida.
3. Escolha **Começar com iCloud**, informe seu nome e crie o espaço apenas no primeiro aparelho.
4. Aguarde os registros serem exportados. Acompanhe o estado em Preferências e os logs do Xcode.
5. Prepare o convite privado com o e-mail iCloud da segunda pessoa e compartilhe o link.
6. No segundo aparelho, use o modo iCloud sem criar um espaço e abra o link. Informe o nome quando a importação terminar.
7. Crie e edite um compromisso em cada lado, verificando que as mudanças chegam ao outro.

O proprietário mantém o espaço no banco privado; a convidada recebe os registros no banco compartilhado. A árvore de registros pertence a uma raiz `Space`. Registros novos são associados à mesma raiz e ao mesmo persistent store.

O convite conta como a segunda vaga antes de ser aceito. A interface recusa convidar outra conta se essa vaga estiver ocupada. Não há compartilhamento público. O link não concede acesso a contas não convidadas.

## 3. Schema de desenvolvimento e produção

Use o CloudKit Console para conferir os tipos gerados a partir de `Space` e `Entry`. No ambiente Development, crie um item de cada tipo e confirme a exportação. Caso o schema ainda não exista, o Xcode permite inicializá-lo em uma execução de desenvolvimento com `NSPersistentCloudKitContainer.initializeCloudKitSchema(options:)`; execute apenas em Debug e remova a chamada antes da distribuição.

Antes do TestFlight, faça **Deploy Schema Changes** de Development para Production no CloudKit Console. Dados não são copiados por essa ação. Instalações Xcode/Development e TestFlight/Production não compartilham o mesmo histórico. Para testar o casal, use a mesma distribuição nos dois aparelhos.

## 4. Instalar o widget

Compile app e extensão com o mesmo Team ID e App Group. Abra o app pelo menos uma vez e adicione o widget na tela inicial. Se aparecer o convite para abrir o app mesmo com dados disponíveis, confira os App Groups nos dois perfis de assinatura. O painel Preferências exibe aviso se o diretório do grupo não estiver disponível.

## 5. Distribuir pelo TestFlight

1. Crie um registro de app no App Store Connect usando o Bundle ID configurado.
2. Confira o schema em Production e incremente `CURRENT_PROJECT_VERSION` a cada envio.
3. No Xcode, selecione um destino de dispositivo e execute **Product → Archive**.
4. Use **Distribute App → App Store Connect**; valide e envie com a sua conta.
5. Configure as informações de teste e adicione vocês como testadores. Se usar teste externo, cumpra a revisão beta exigida pela Apple.
6. Instale pelo TestFlight nos dois iPhones e repita o teste com contas iCloud diferentes.

Uma build TestFlight pode ser usada por até 90 dias. Será necessário enviar novas builds para continuar usando esse canal. TestFlight não significa publicar o app na App Store. Este repositório não automatiza assinatura nem envio: essas etapas dependem da sua equipe Apple.

## Recuperação

- **iCloud indisponível:** confira a conta no iPhone e toque em Verificar conta e sincronização. Itens salvos localmente aguardam sincronização.
- **Convite não abre:** confira a instalação, `CKSharingSupported`, o e-mail convidado e o ambiente Development/Production.
- **Duas pessoas criaram espaços:** não há mesclagem automática. Escolha o espaço que será usado; preserve manualmente qualquer conteúdo necessário antes de remover uma instalação de teste. A interface não aceita um convite por cima de um espaço próprio.
- **Troca de conta iCloud:** encerre a sessão do app e remova seus dados locais antes de entregar o aparelho a outra pessoa. O cache local é acessível à pessoa que usa o aparelho desbloqueado.
- **Sair/encerrar:** a ação usa a remoção da zona compartilhada. Para o proprietário, remove o espaço compartilhado; para o participante, remove acesso e cópia local. Leia a confirmação antes de executar e preserve informações necessárias. Não há exportação/restauração no app nesta versão.

## Referências oficiais

- [Compartilhar objetos Core Data entre usuários iCloud](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users)
- [Exemplo Apple de compartilhamento CloudKit](https://github.com/apple/sample-cloudkit-sharing)
- [Atualização de widgets](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [TestFlight e validade das builds](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
