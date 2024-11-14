
local luaxml_sty = require "luaxml-sty"
-- try 
local xmltransform = luaxml_sty.transformations.html
if not xmltransform then
  xmltransform = luaxml_sty.declare_transformer("html")
end


xmltransform:add_action("head", [[
\tableofcontents
]])

xmltransform:add_action("img", [[\noindent\includegraphics[max width=\textwidth]{@{src}}]])

xmltransform:add_action("h1", [[\addcontentsline{toc}{section}{%s}\section*{%s}
]])
xmltransform:add_action("h2", [[\addcontentsline{toc}{subsection}{%s}\subsection*{%s}
]])
-- don't add lower sectioning level than subsection
xmltransform:add_action("h3", [[\addcontentsline{toc}{subsubsection}{%s}\subsubsection*{%s}
]])
xmltransform:add_action("h4", [[\addcontentsline{toc}{subsubsection}{%s}\subsubsection*{%s}
]])
xmltransform:add_action("h5", [[\addcontentsline{toc}{subsubsection}{%s}\subsubsection*{%s}
]])
xmltransform:add_action("h6", [[\addcontentsline{toc}{subsubsection}{%s}\subsubsection*{%s}
]])

xmltransform:add_action("i", [[\textit{%s}]])
xmltransform:add_action("em", [[\emph{%s}]])
xmltransform:add_action("b", [[\textbf{%s}]])
xmltransform:add_action("strong", [[\textbf{%s}]])
xmltransform:add_action("tt", [[\texttt{%s}]])
xmltransform:add_action("samp", [[\texttt{%s}]])
xmltransform:add_action("kbd", [[\texttt{%s}]])
xmltransform:add_action("var", [[\textit{%s}]])
xmltransform:add_action("dfn", [[\texttt{%s}]])
xmltransform:add_action("code", [[\texttt{%s}]])
xmltransform:add_action("a[href]", [[\textit{%s}\protect\footnote{\texttt{@{href}}}]])


local itemize = [[
\begin{itemize}
%s
\end{itemize}
]]
xmltransform:add_action("ul", itemize)
xmltransform:add_action("menu", itemize)
xmltransform:add_action("ol", [[
\begin{enumerate}
%s
\end{enumerate}
]])

xmltransform:add_action("dl", [[
\begin{description}
%s
\end{description}
]])


xmltransform:add_action("li", "\\item %s\n")
xmltransform:add_action("dt", "\\item[%s] ")

local quote = [[
\begin{quotation}
%s
\end{quotation}
]]

xmltransform:add_action("blockquote", quote)
xmltransform:add_action("q", "\\enquote{%s}")
xmltransform:add_action("abbr", "%s\\protect\\footnote{@{title}}")
xmltransform:add_action("sup", "\\textsuperscript{%s}")
xmltransform:add_action("sub", "\\textsubscript{%s}")

xmltransform:add_action("table", [[
\begin{calstable}
%s
\end{calstable}
]])

xmltransform:add_action("tr", "\\brow %s \\erow")
xmltransform:add_action("td", "\\cell{%s}")
xmltransform:add_action("th", "\\cell{%s}")


-- this is the original code for verbatim, but I changed LuaXML to not escape characters in verbatim,
-- so we can use the verbatim environment
xmltransform:add_action("pre", [[{\parindent=0pt\obeylines\ttfamily\catcode`\ =\active\def {\ }\catcode`\#=11%%
%s}

]], {verbatim=true})
xmltransform:add_action("pre *", [[%s]])

-- 
xmltransform:add_action("pre", [[
\begin{verbatim}%s\end{verbatim}
]], {verbatim=true})

xmltransform:add_action("details", [[%s
]])

xmltransform:add_action("details summary", [[
\medskip
\noindent %s

\smallskip
\noindent
]])

xmltransform:add_action("figure", [[
\begin{figure}[hbt!]
\centering

%s

\end{figure}
]])

xmltransform:add_action("figcaption", [[\caption{%s}]])


xmltransform:add_action("p", [[

%s

]])

xmltransform:add_action("br", [[\\]])

-- some fixes for weird web pages
xmltransform:add_action("a p", [[%s]])
xmltransform:add_action("h1 a[href], h2 a[href], h3 a[href], h4 a[href], h5 a[href], h6 a[href]", "%s")


-- mathjax is special element added by rmodepdf around LaTeX math
xmltransform:add_action("mathjax",[[%s]], {verbatim=true,collapse_newlines=false})

xmltransform:add_action("hyperlink", "\\hyperlink{@{href}}{%s}")
xmltransform:add_action("hypertarget", "\\hypertarget{@{id}}{%s}")

return xmltransform
