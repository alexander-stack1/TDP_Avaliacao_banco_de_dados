import controlador.Diagrama;
import controlador.Editor;
import controlador.apoios.GuardaPadraoBrM;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.FileOutputStream;
import java.io.ObjectOutputStream;
import javax.imageio.ImageIO;
import org.w3c.dom.Document;

/**
 * Abre o XML nativo do brModelo 3 com as próprias classes do programa e grava
 * o arquivo .brM3 (serialização Java oficial, exatamente como Diagrama.Salvar faz)
 * e um PNG do diagrama. Não passa pela janela principal (menus, inspector).
 *
 * Compilar/executar (a partir da pasta do brModelo.jar, para que ele crie o config.chc ali):
 *   javac -cp brModelo.jar -d out ConverteBrM3.java
 *   java  -cp brModelo.jar:out ConverteBrM3 entrada.xml saida.brM3 saida.png
 */
public class ConverteBrM3 {
    public static void main(String[] args) throws Exception {
        File xml = new File(args[0]);
        File brm3 = new File(args[1]);
        File png = new File(args[2]);

        Editor editor = new Editor();
        Document doc = util.XMLGenerate.LoadDocument(xml);
        Diagrama d = editor.Novo(Diagrama.TipoDeDiagrama.tpConceitual);
        boolean carregou = d.LoadFromXML(doc, false);
        for (util.BrLogger.Excecao ex : util.BrLogger.Logs) {
            System.out.println("brModelo log: " + ex.Tipo + " | " + ex.Complemento + " | " + ex.Valor);
        }
        // LoadFromXML termina chamando PerformInspector() (painel da janela principal, ausente aqui);
        // todos os itens ja foram criados e ligados (CommitXML) antes disso.
        if (!carregou && d.getListaDeItens().isEmpty()) {
            System.err.println("ERRO: XML nao carregou");
            System.exit(1);
        }
        d.ReGeraUniversalUnicID();
        String nome = brm3.getName().replaceAll("\\.brM3$", "");
        d.SetNome(nome);
        d.setArquivo("");
        System.out.println("itens carregados: " + d.getListaDeItens().size());

        // caixa envolvente para o PNG
        int w = 0, h = 0;
        for (Object o : d.getListaDeItens()) {
            if (o instanceof desenho.Elementar) {
                desenho.Elementar e = (desenho.Elementar) o;
                w = Math.max(w, e.getLeft() + e.getWidth());
                h = Math.max(h, e.getTop() + e.getHeight());
            }
        }
        w += 40; h += 40;

        // mesmo conteudo que Diagrama.Salvar(File) grava para .brM3
        GuardaPadraoBrM seg = new GuardaPadraoBrM(d);
        seg.versaoDiagrama = d.getVersao();
        try (ObjectOutputStream out = new ObjectOutputStream(new FileOutputStream(brm3))) {
            out.writeObject(seg);
        }
        System.out.println("brM3 salvo: " + brm3 + " (" + brm3.length() + " bytes, versao " + seg.versaoDiagrama + ")");

        // prova: reabrir o .brM3 gravado exatamente como o brModelo faz (Diagrama.LoadFromFile)
        try (java.io.ObjectInputStream in = new java.io.ObjectInputStream(new java.io.FileInputStream(brm3))) {
            GuardaPadraoBrM lido = (GuardaPadraoBrM) in.readObject();
            Diagrama d2 = lido.getDiagrama();
            System.out.println("round-trip .brM3: " + (d2 == null ? "FALHOU" : d2.getListaDeItens().size() + " itens, versao " + lido.versaoDiagrama));
        }

        BufferedImage img = util.ImageGenerate.geraImagemForPrn(d, w, h);
        ImageIO.write(img, "png", png);
        System.out.println("png salvo: " + png + " " + w + "x" + h);
        System.exit(0);
    }
}
