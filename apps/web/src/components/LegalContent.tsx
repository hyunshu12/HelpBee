import { Container } from './Container';

export type LegalSection = { heading: string; body: string };

export function LegalContent({
  title,
  updated,
  intro,
  sections,
}: {
  title: string;
  updated: string;
  intro: string;
  sections: LegalSection[];
}) {
  return (
    <Container className="max-w-3xl py-16 md:py-24">
      <h1 className="text-3xl font-bold text-bee-black md:text-4xl">{title}</h1>
      <p className="mt-2 text-base text-bee-black/60">{updated}</p>
      <p className="mt-6 text-lg leading-relaxed text-bee-black/80">{intro}</p>
      <div className="mt-10 space-y-8">
        {sections.map((s, i) => (
          <section key={i}>
            <h2 className="text-xl font-bold text-bee-black">{s.heading}</h2>
            <p className="mt-2 whitespace-pre-line text-lg leading-relaxed text-bee-black/80">
              {s.body}
            </p>
          </section>
        ))}
      </div>
    </Container>
  );
}
